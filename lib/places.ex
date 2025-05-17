defmodule Bonfire.Geolocate.Places do
  alias Bonfire.Common.Utils

  def fetch_places(opts) do
    with {:ok, places} <-
           Utils.maybe_apply(Bonfire.Geolocate.GraphQL, :geolocations, [
             %{limit: 15},
             %{
               context: %{current_user: Utils.current_user(opts)}
             }
           ]) do
      # [
      #   %{id: 1, lat: 51.5, long: -0.09, selected: false},
      #   %{id: 2, lat: 51.5, long: -0.099, selected: true}
      # ]

      places
    else
      #  TODO: cleanup
      _ ->
        Bonfire.Geolocate.Geolocations.many_paginated(opts)
    end
  end

  def fetch_place_things(filters, opts) do
    with {:ok, things} <-
           Bonfire.Geolocate.Geolocations.many_paginated(filters) do
      things
    else
      _e ->
        fetch_places(opts)
    end
  end

  def fetch_place(id, opts) do
    with {:ok, place} <-
           Utils.maybe_apply(Bonfire.Geolocate.GraphQL, :geolocation, [
             %{id: id},
             %{
               context: %{current_user: Utils.current_user(opts)}
             }
           ]) do
      place
    else
      #  TODO: cleanup
      _ ->
        Bonfire.Geolocate.Geolocations.one(id: id, user: Utils.current_user(opts))
    end
  end
end
