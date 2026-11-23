# SPDX-License-Identifier: AGPL-3.0-only

# check that this extension is configured
Bonfire.Common.Config.require_extension_config!(:bonfire_geolocate)

defmodule Bonfire.Geolocate.Geolocations do
  import Bonfire.Common.Config, only: [repo: 0]
  use Bonfire.Common.Utils
  use Arrows
  # alias Bonfire.Geolocate

  alias Bonfire.Geolocate.Geolocation
  alias Bonfire.Geolocate.Queries

  # alias CommonsPub.Characters
  # alias CommonsPub.Feeds.FeedActivities
  # alias CommonsPub.Activities
  # alias CommonsPub.Feeds

  @postgis_srid 4326

  @behaviour Bonfire.Federate.ActivityPub.FederationModules
  def federation_module, do: ["Place", "SpatialThing", "geojson:Feature"]

  def cursor(:followers), do: &[&1.follower_count, &1.id]
  def test_cursor(:followers), do: &[&1["followerCount"], &1["id"]]

  @doc """
  Retrieves a single geolocation by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for geolocations (inc. tests)
  """
  def one(filters) do
    with {:ok, result} <- repo().single(Queries.query(Geolocation, filters)) do
      {:ok, populate_coordinates(result)}
    end
  end

  @doc """
  Retrieves a list of geolocations by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for geolocations (inc. tests)
  """
  def many(filters \\ []),
    do: {:ok, repo().many(Queries.query(Geolocation, filters))}

  def many!(filters \\ []), do: repo().many(Queries.query(Geolocation, filters))

  # def many_paginated(filters \\ []) do
  #   with {:ok, %{edges: edges} = page} <-
  #          repo().many_paginated(Queries.query(Geolocation, filters)) do
  #     edges = Enum.map(edges, &populate_coordinates/1)
  #     {:ok, %{page | edges: edges}}
  #   end
  # end
  # `repo().many_paginated/1` returns the page itself, not `{:ok, page}`
  def many_paginated(filters \\ []) do
    case repo().many_paginated(Queries.query(Geolocation, filters)) do
      %{edges: edges} = page ->
        {:ok, %{page | edges: Enum.map(edges, &populate_coordinates/1)}}

      other ->
        error(other, "Could not list places")
    end
  end

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
  def create(creator, context, attrs, opts \\ [])

  def create(creator, context, attrs, opts) when is_map(attrs) do
    with {:ok, item} <-
           repo().transact_with(fn ->
             with {:ok, attrs} <- resolve_mappable_address(attrs),
                  {:ok, item} <- insert_geolocation(creator, attrs, context: context) do
               {:ok, populate_coordinates(item)}
               #  |> debug("created")
             end
           end) do
      #  FIXME: we should publish by default but assigning boundaries is failing (results in a postgres foreign key error where the object id is not found in the pointer table)
      if !Keyword.get(opts, :skip_publish, true),
        do:
          maybe_apply(Bonfire.Social.Objects, :publish, [
            creator,
            :create,
            item,
            attrs,
            __MODULE__
          ])

      if !opts[:skip_search_index],
        do: maybe_apply(Bonfire.Search, :maybe_index, [item, nil, creator], creator)

      {:ok, item}
    end
  rescue
    e in Postgrex.QueryError ->
      error(e, "!!! Error saving the geo coordinate in DB")
      insert_geolocation(creator, attrs, context: context, skip_geom: true)
  end

  @spec create(any(), attrs :: map) ::
          {:ok, Geolocation.t()} | {:error, Changeset.t()}
  def create(creator, attrs) when is_map(attrs) do
    create(creator, nil, attrs)
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
      # checked as the user: whoever owns the thing may tag it, anyone else needs the `:tag` permission, and no user is refused
      maybe_apply(Bonfire.Tag, :tag_something, [
        user,
        thing,
        geolocation,
        true,
        [current_user: user]
      ])
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

  def populate_coordinates(objects) when is_list(objects) do
    Enum.map(objects, &populate_coordinates/1)
  end

  # def populate_coordinates(%{geom: %{coordinates: {lat, long}}} = object) do
  # a point is stored longitude first (x), as `Geo.Point` and PostGIS have it
  def populate_coordinates(%{geom: %{coordinates: {long, lat}}} = object) do
    # debug(lat)
    Map.merge(object, %{lat: lat, long: long})
  end

  def populate_coordinates(%{geom: %{coordinates: _} = geom} = object) do
    # debug(populate_coordinates: lat)
    {lat, long} = extract_coordinates(geom)
    Map.merge(object, %{lat: lat, long: long})
  end

  def populate_coordinates(geo), do: (geo || %{}) |> debug("could not find coords")

  # Common function to extract both coordinates at once (returns {lat, long})
  def extract_coordinates(geom) when is_struct(geom) do
    case geom do
      # Point types (direct access)
      %type{coordinates: coordinates}
      when type in [Geo.Point, Geo.PointZ, Geo.PointM, Geo.PointZM] ->
        extract_points(coordinates)

      # Line types (first point)
      %type{coordinates: coordinates}
      when type in [Geo.LineString, Geo.LineStringZ, Geo.LineStringZM] ->
        coordinates |> List.first() |> extract_points()

      # Polygon types (first point of outer ring)
      %type{coordinates: coordinates} when type in [Geo.Polygon, Geo.PolygonZ] ->
        coordinates |> List.first() |> List.first() |> extract_points()

      # Multi-point types (first point)
      %type{coordinates: coordinates} when type in [Geo.MultiPoint, Geo.MultiPointZ] ->
        coordinates |> List.first() |> extract_points()

      # Multi-line types (first point of first line)
      %type{coordinates: coordinates} when type in [Geo.MultiLineString, Geo.MultiLineStringZ] ->
        coordinates |> List.first() |> List.first() |> extract_points()

      # Multi-polygon types (first point of first polygon's outer ring)
      %type{coordinates: coordinates} when type in [Geo.MultiPolygon, Geo.MultiPolygonZ] ->
        coordinates |> List.first() |> List.first() |> List.first() |> extract_points()

      # Collection - try first geometry
      %Geo.GeometryCollection{geometries: [first | _]} ->
        extract_coordinates(first)

      %Geo.GeometryCollection{} ->
        warn(geom, "Unsupported GeometryCollection")
        {0, 0}

      # Fallback for unknown or empty structures
      %{coordinates: coordinates} ->
        try do
          extract_points(coordinates)
        rescue
          e ->
            warn(e, "Could not extract coordinates")
            debug(geom)
            {0, 0}
        end

      _ ->
        warn(geom, "Unsupported geometry type")
        {0, 0}
    end
  end

  def extract_coordinates(%{coordinates: coordinates} = geom) do
    try do
      extract_points(coordinates)
    rescue
      e ->
        warn(e, "Could not extract coordinates")
        debug(geom)
        {0, 0}
    end
  end

  def extract_coordinates(other) do
    warn(other, "Could not extract coordinates")
    {0, 0}
  end

  # Helper function to extract both lat and long from a point
  # a position is longitude first (x, then y), as `Geo` and GeoJSON have it; returns `{lat, long}`
  defp extract_points(coords) when is_tuple(coords) and tuple_size(coords) >= 2 do
    try do
      # {elem(coords, 0), elem(coords, 1)}
      {elem(coords, 1), elem(coords, 0)}
    rescue
      e ->
        warn(e, "Could not extract coordinates")
        debug(coords)
        {0, 0}
    end
  end

  defp extract_points(coords) when is_list(coords) and length(coords) >= 2 do
    # {Enum.at(coords, 0, 0), Enum.at(coords, 1, 0)}
    {Enum.at(coords, 1, 0), Enum.at(coords, 0, 0)}
  end

  defp extract_points(other) do
    warn(other, "Could not extract coordinates")
    {0, 0}
  end

  def resolve_mappable_address(%{mappable_address: address} = attrs)
      when is_binary(address) do
    if is_nil(geocodable_name(address)) do
      # text that is not a place (eg. "Online", or a URL) is kept as the place's text, but not geocoded
      {:ok, attrs}
    else
      geocode_mappable_address(attrs, address)
    end
  end

  def resolve_mappable_address(attrs), do: {:ok, attrs}

  defp geocode_mappable_address(attrs, address) do
    with {:ok, coords} <-
           known_coordinates(address) || Bonfire.Geolocate.Geocode.coordinates(address) do
      # debug(attrs)
      # debug(coords)
      # TODO: should take bounds and save in `geom`
      {:ok, Map.put(Map.put(attrs, :lat, coords.lat), :long, coords.lon)}
    else
      reason ->
        # the place is still saved, just not on the map
        warn(reason, "Could not geocode the address, so it has no coordinates: #{address}")
        {:ok, attrs}
    end
  end

  # the point of a place already saved with the same address (trimmed, any case), instead of asking the geocoder again
  defp known_coordinates(address) do
    require Ecto.Query
    normalised = address |> String.trim() |> String.downcase()

    Ecto.Query.from(g in Geolocation,
      where: fragment("lower(trim(?))", g.mappable_address) == ^normalised and not is_nil(g.geom),
      select: g.geom,
      limit: 1
    )
    |> repo().one()
    |> case do
      nil ->
        nil

      geom ->
        {lat, long} = extract_coordinates(geom)
        {:ok, %{lat: lat, lon: long}}
    end
  end

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

  def ap_receive_activity(creator, activity, %{data: %{"type" => "Geolocation"}} = object) do
    ValueFlows.Util.Federation.ap_receive_activity(
      creator,
      activity,
      object,
      &create/2
    )
  end

  def ap_receive_activity(creator, activity, %{data: data} = object) do
    debug(activity, "activity")

    warn(
      object,
      "received"
    )

    create(creator, nil, ap_attrs(data))
  end

  @doc "The attrs of a geolocation read from an AS2 `Place`: name, summary, latitude, longitude and `geojson:hasGeometry`."
  def ap_attrs(data) do
    lat = e(data, "latitude", nil)
    long = e(data, "longitude", nil)
    geom = extract_geojson_geometry(e(data, "geojson:hasGeometry", nil))
    name = e(data, "name", nil)

    %{
      name: name,
      note: e(data, "summary", nil),
      #  TODO?
      mappable_address: ap_mappable_address(data, name, has_coordinates?(data, lat, long, geom)),
      lat: lat,
      long: long,
      geom: geom,
      is_public: true
    }
    |> debug("aatrrs")
  end

  # a Place that has coordinates (or a geometry) keeps them and is not geocoded; its `geo` is not read
  defp has_coordinates?(_data, lat, long, geom),
    do: not is_nil(geom) or (not is_nil(lat) and not is_nil(long))

  # the text to geocode: the address (a Schema.org `PostalAddress`, or a plain string), else the name unless that is not a place (eg. "Online")
  defp ap_mappable_address(_data, _name, true), do: nil

  defp ap_mappable_address(data, name, false),
    do: ap_address_text(e(data, "address", nil)) || geocodable_name(name)

  defp geocodable_name(name) do
    name = non_blank(name)

    if name && not Bonfire.Common.URIs.looks_like_url?(name) && not non_place_name?(name),
      do: name
  end

  # a name that is a listed word, or a short one (up to the configured number of words, with no comma) that has a listed word among its words
  defp non_place_name?(name) do
    words = name |> String.downcase() |> String.split()
    listed = non_place_names()
    max_words = Config.get([Bonfire.Geolocate, :non_place_name_max_words], 3)

    String.downcase(name) in listed or
      (length(words) <= max_words and not String.contains?(name, ",") and
         Enum.any?(words, &(&1 in listed)))
  end

  defp non_place_names do
    Config.get([Bonfire.Geolocate, :non_place_names], [])
    |> Enum.map(&String.downcase/1)
  end

  defp ap_address_text(%{} = address) do
    ~w(streetAddress postalCode addressLocality addressRegion addressCountry)
    |> Enum.map(&non_blank(address[&1]))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  defp ap_address_text(address), do: non_blank(address)

  defp non_blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp non_blank(value) when is_integer(value), do: Integer.to_string(value)
  defp non_blank(_), do: nil

  # Extract and convert GeoJSON geometry from ActivityPub object
  def extract_geojson_geometry(%{"type" => type, "coordinates" => coordinates}) do
    case type do
      "Point" ->
        # Handle Point type
        [lon, lat] = List.flatten(coordinates)
        %Geo.Point{coordinates: {lat, lon}, srid: @postgis_srid}

      "Polygon" ->
        # Handle Polygon type
        coords =
          Enum.map(coordinates, fn ring ->
            Enum.map(ring, fn [lon, lat] -> {lat, lon} end)
          end)

        %Geo.Polygon{coordinates: coords, srid: @postgis_srid}

      "LineString" ->
        # Handle LineString type
        coords = Enum.map(coordinates, fn [lon, lat] -> {lat, lon} end)
        %Geo.LineString{coordinates: coords, srid: @postgis_srid}

      "MultiPolygon" ->
        # Handle MultiPolygon type
        coords =
          Enum.map(coordinates, fn polygon ->
            Enum.map(polygon, fn ring ->
              Enum.map(ring, fn [lon, lat] -> {lat, lon} end)
            end)
          end)

        %Geo.MultiPolygon{coordinates: coords, srid: @postgis_srid}

      other ->
        error(other, "Unsupported GeoJSON type")
        nil
    end
  end

  def extract_geojson_geometry(_), do: nil

  @km_per_degree 111.195

  @doc """
  The box that holds the circle of `km` around a point, as a map takes it to fit its view: `[[south, west], [north, east]]` in degrees (a degree of longitude is shorter away from the equator, and the box is held to the globe). Nil for something that is not a point and a radius.

      iex> Bonfire.Geolocate.Geolocations.bounds_around(0, 0, 111.195)
      [[-1.0, -1.0], [1.0, 1.0]]
  """
  def bounds_around(lat, long, km)
      when is_number(lat) and is_number(long) and is_number(km) and km > 0 do
    dlat = km / @km_per_degree
    # at the poles every longitude is within reach
    dlong = min(km / (@km_per_degree * max(:math.cos(lat * :math.pi() / 180), 0.0001)), 180.0)

    [
      [max(lat - dlat, -90.0) * 1.0, max(long - dlong, -180.0) * 1.0],
      [min(lat + dlat, 90.0) * 1.0, min(long + dlong, 180.0) * 1.0]
    ]
  end

  def bounds_around(_, _, _), do: nil
end
