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

      places.edges
    else
      _e ->
        nil
    end
  end

  def fetch_place_things(filters, opts) do
    with {:ok, things} <-
           Bonfire.Geolocate.Geolocations.many(filters) do
      things
    else
      _e ->
        fetch_places(opts)
    end
  end

  def fetch_place(id, opts) do
    with {:ok, place} <-
           Bonfire.Geolocate.GraphQL.geolocation(%{id: id}, %{
             context: %{current_user: Utils.current_user(opts)}
           }) do
      place
    else
      _e ->
        nil
    end
  end
end
