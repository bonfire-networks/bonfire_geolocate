# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Geolocate.PrimaryGeolocations do
  @moduledoc "The main location of any object (eg a profile, a post, an event), kept in the `PrimaryGeolocation` mixin."

  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Geolocate.PrimaryGeolocation
  alias Bonfire.Common.Enums

  @doc "Sets the main location of `object` to `geolocation`, replacing any it had."
  def set(object, geolocation) do
    %PrimaryGeolocation{id: Enums.id(object)}
    |> PrimaryGeolocation.changeset(%{geolocation_id: Enums.id(geolocation)})
    |> repo().insert(on_conflict: {:replace, [:geolocation_id]}, conflict_target: :id)
  end

  @doc "Removes the main location of `object`. The geolocation itself stays."
  def remove(object) do
    import Ecto.Query

    {count, _} =
      repo().delete_all(from(pg in PrimaryGeolocation, where: pg.id == ^Enums.id(object)))

    {:ok, count}
  end
end
