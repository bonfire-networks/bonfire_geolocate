defmodule Bonfire.Geolocate.Acts.PrimaryGeolocation do
  @moduledoc """
  Makes a place and sets it as the object's primary geolocation. The place is inserted by `Bonfire.Ecto.Acts.Work` in the same transaction as the object, so an object that fails to be created leaves no place behind. A name or address is geocoded here, before the transaction.

  Epic Options:
    * `:current_user` - the creator of the place.

  Act Options:
    * `:on` - key in assigns to find the changeset, required.
    * `:attrs` - epic options key to find the attributes at, default: `:post_attrs`. The place is their `:place`: a name or address, or a map of `Bonfire.Geolocate.Geolocation` attrs (eg. from `Bonfire.Geolocate.Geolocations.ap_attrs/1`).
  """
  use Bonfire.Common.Utils
  alias Bonfire.Epics
  alias Bonfire.Epics.Epic
  alias Bonfire.Geolocate.Geolocation
  alias Bonfire.Geolocate.Geolocations
  alias Bonfire.Geolocate.PrimaryGeolocation
  alias Ecto.Changeset
  import Epics

  def run(epic, act) do
    on = Keyword.fetch!(act.options, :on)
    attrs_key = Keyword.get(act.options, :attrs, :post_attrs)
    place = e(Keyword.get(epic.assigns[:options], attrs_key, %{}), :place, nil)

    cond do
      epic.errors != [] ->
        maybe_debug(epic, act, length(epic.errors), "Skipping due to epic errors")
        epic

      place in [nil, ""] ->
        maybe_debug(epic, act, attrs_key, "Skipping because no place given")
        epic

      true ->
        case epic.assigns[on] do
          %Changeset{valid?: true} = changeset ->
            creator = current_user_or_id(epic.assigns[:options])
            smart(epic, act, place, "put place")

            put_place(changeset, place, creator)
            |> Epic.assign(epic, on, ...)

          other ->
            maybe_debug(epic, act, other, "Skipping :#{on} due to changeset")
            epic
        end
    end
  end

  @doc "Puts the place (a name or address, or a map of `Bonfire.Geolocate.Geolocation` attrs) on the changeset as its primary geolocation, to be inserted with it."
  def put_place(changeset, place, creator) when is_binary(place),
    do: put_place(changeset, %{name: place, mappable_address: place}, creator)

  def put_place(changeset, %{} = attrs, creator) do
    {:ok, attrs} = Geolocations.resolve_mappable_address(attrs)

    case Geolocation.create_changeset(creator, attrs) do
      %Changeset{valid?: true} = geolocation ->
        # no `PrimaryGeolocation.changeset/2`, which needs a `geolocation_id`: Ecto inserts the geolocation first and sets it
        primary =
          %PrimaryGeolocation{}
          |> Changeset.change()
          |> Changeset.put_assoc(:geolocation, geolocation)
          |> Changeset.assoc_constraint(:geolocation)

        Changeset.put_assoc(changeset, :primary_geolocation, primary)

      invalid ->
        # the object is made without the place, rather than refused
        warn(invalid, "Could not use the place")
        changeset
    end
  end
end
