defmodule Bonfire.Geolocate.Places do
  alias Bonfire.Common.Utils

  def fetch_places(socket) do
    with {:ok, places} <-
           Bonfire.Geolocate.GraphQL.geolocations(%{limit: 15}, %{
             context: %{current_user: Utils.current_user(socket)}
           }) do
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

  def fetch_place_things(filters, socket) do
    with {:ok, things} <-
           Bonfire.Geolocate.Geolocations.many(filters) do
      things
    else
      _e ->
        fetch_places(socket)
    end
  end

  def fetch_place(id, socket) do
    with {:ok, place} <-
           Bonfire.Geolocate.GraphQL.geolocation(%{id: id}, %{
             context: %{current_user: Utils.current_user(socket)}
           }) do
      place
    else
      _e ->
        nil
    end
  end
end
