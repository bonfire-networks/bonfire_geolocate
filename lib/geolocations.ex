# SPDX-License-Identifier: AGPL-3.0-only

# check that this extension is configured
Bonfire.Common.Config.require_extension_config!(:bonfire_geolocate)

defmodule Bonfire.Geolocate.Geolocations do
  import Bonfire.Common.Config, only: [repo: 0]
  use Bonfire.Common.Utils
  # alias Bonfire.Geolocate

  alias Bonfire.Geolocate.Geolocation
  alias Bonfire.Geolocate.Queries

  # alias CommonsPub.Characters
  # alias CommonsPub.Feeds.FeedActivities
  # alias CommonsPub.Activities
  # alias CommonsPub.Feeds

  @behaviour Bonfire.Federate.ActivityPub.FederationModules
  def federation_module, do: ["Place", "SpatialThing"]

  def cursor(:followers), do: &[&1.follower_count, &1.id]
  def test_cursor(:followers), do: &[&1["followerCount"], &1["id"]]

  @doc """
  Retrieves a single geolocation by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for geolocations (inc. tests)
  """
  def one(filters), do: repo().single(Queries.query(Geolocation, filters))

  @doc """
  Retrieves a list of geolocations by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for geolocations (inc. tests)
  """
  def many(filters \\ []),
    do: {:ok, repo().many(Queries.query(Geolocation, filters))}

  def many!(filters \\ []), do: repo().many(Queries.query(Geolocation, filters))

  def search(search, opts \\ []) do
    maybe_apply(
      Bonfire.Search,
      :search_by_type,
      [search, Geolocation, opts],
      &none/2
    ) || many!(autocomplete: search)
  end

  defp none(_, _), do: []

  ## mutations

  @spec create(any(), context :: any, attrs :: map) ::
          {:ok, Geolocation.t()} | {:error, Changeset.t()}
  # TODO deprecate in favour of create/2
  def create(creator, %{} = context, attrs) when is_map(attrs) do
    repo().transact_with(fn ->
      with {:ok, attrs} <- resolve_mappable_address(attrs),
           {:ok, item} <- insert_geolocation(creator, attrs, context: context) do
        maybe_apply(Bonfire.Social.Objects, :publish, [
          creator,
          :create,
          item,
          attrs,
          __MODULE__
        ])

        maybe_apply(Bonfire.Search, :maybe_index, [item, nil, creator], creator)

        debug({:ok, populate_result(item)})
      end
    end)
  rescue
    e in Postgrex.QueryError ->
      error(e, "!!! Error saving the geo coordinate in DB")
      insert_geolocation(creator, attrs, context: context, skip_geom: true)
  end

  def create(creator, _, attrs) when is_map(attrs) do
    create(creator, attrs)
  end

  @spec create(any(), attrs :: map) ::
          {:ok, Geolocation.t()} | {:error, Changeset.t()}
  def create(creator, attrs) when is_map(attrs) do
    repo().transact_with(fn ->
      with {:ok, attrs} <- resolve_mappable_address(attrs),
           {:ok, item} <- insert_geolocation(creator, attrs) do
        # FIXME: use publishing logic in from a different repo
        maybe_apply(Bonfire.Social.Objects, :publish, [
          creator,
          # :create,
          nil,
          item,
          attrs,
          __MODULE__
        ])

        maybe_apply(Bonfire.Search, :maybe_index, [item, nil, creator], creator)

        debug({:ok, populate_result(item)})
      end
    end)
  rescue
    e in Postgrex.QueryError ->
      error(e, "!!! Error saving the geo coordinate in DB")

      attrs
      |> debug()
      |> insert_geolocation(creator, ..., skip_geom: true)
  end

  defp insert_geolocation(creator, attrs, opts \\ []) do
    # TODO: should the mappable_address field be unique?
    cs = Geolocation.create_changeset(creator, attrs, opts)
    with {:ok, item} <- repo().insert(cs), do: {:ok, item}
  end

  def thing_add_location(user, thing, mappable_address)
      when is_binary(mappable_address) do
    with {:ok, geolocation} <-
           create(user, %{
             name: mappable_address,
             mappable_address: mappable_address
           }) do
      maybe_apply(Bonfire.Tag, :tag_something, [user, thing, geolocation])
    end
  end

  @spec update(any(), Geolocation.t(), attrs :: map) ::
          {:ok, Geolocation.t()} | {:error, Changeset.t()}
  def update(user, %Geolocation{} = geolocation, attrs) do
    # FIXME :ok <- ap_publish(user, :update, item)
    with {:ok, attrs} <- resolve_mappable_address(attrs),
         {:ok, item} <-
           repo().update(Geolocation.update_changeset(geolocation, attrs)) do
      maybe_apply(Bonfire.Search, :maybe_index, [geolocation, nil, user], user)

      {:ok, populate_coordinates(item)}
    end
  end

  @spec soft_delete(Geolocation.t(), any()) ::
          {:ok, Geolocation.t()} | {:error, Changeset.t()}
  def soft_delete(%Geolocation{} = geo, _opts) do
    repo().transact_with(fn ->
      # FIXME :ok <- ap_publish(user, :delete, geo)
      with {:ok, geo} <- Bonfire.Common.Repo.Delete.soft_delete(geo) do
        {:ok, geo}
      end
    end)
  end

  def populate_result(geo) do
    populate_coordinates(geo)
  end

  def populate_coordinates(objects) when is_list(objects) do
    Enum.map(objects, &populate_coordinates/1)
  end

  def populate_coordinates(%{geom: %{coordinates: {lat, long}}} = object) do
    # debug(populate_coordinates: lat)
    Map.merge(object, %{lat: lat, long: long})
  end

  # |> debug("could not find coords")
  def populate_coordinates(geo), do: geo || %{}

  def resolve_mappable_address(%{mappable_address: address} = attrs)
      when is_binary(address) do
    with {:ok, coords} <- Bonfire.Geolocate.Geocode.coordinates(address) do
      # debug(attrs)
      # debug(coords)
      # TODO: should take bounds and save in `geom`
      {:ok, Map.put(Map.put(attrs, :lat, coords.lat), :long, coords.lon)}
    else
      _ -> {:ok, attrs}
    end
  end

  def resolve_mappable_address(attrs), do: {:ok, attrs}

  def indexing_object_format(u) do
    # debug(obj)

    %{
      "id" => u.id,
      "index_type" => Types.module_to_str(Geolocation),
      # "url" => url_path(obj),
      "name" => e(u, :name, ""),
      "note" => e(u, :note, ""),
      "mappable_address" => e(u, :mappable_address, "")
    }

    # |> IO.inspect
  end

  def ap_publish_activity(subject, activity_name, thing) do
    ValueFlows.Util.Federation.ap_publish_activity(
      subject,
      activity_name,
      :spatial_thing,
      thing,
      2,
      []
    )
  end

  def ap_receive_activity(creator, activity, object) do
    ValueFlows.Util.Federation.ap_receive_activity(
      creator,
      activity,
      object,
      &create/2
    )
  end
end
