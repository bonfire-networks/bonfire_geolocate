defmodule Bonfire.Geolocate.MapLive do
  use Bonfire.Web, :live_component

  import Bonfire.Geolocate.Places

  @postgis_srid 4326

  def update(%{id: id} = assigns, socket) when is_binary(id) do
    show_place_things(id, socket)
  end

  def update(assigns, socket) do
    fetch_places(socket) |> mark_places(socket)
  end

  def handle_event("marker_click", %{"id" => id} = _params, socket) do
    IO.inspect(click: id)

    show_place_things(id, socket)
  end

  def handle_event(
        "bounds",
        polygon,
        socket
      ) do
    IO.inspect(bounds: polygon)

    show_place_things(Enum.at(polygon, 0), socket)
  end

  # def handle_event("toggle_marker", %{"id" => id} = _params, socket) do
  #   {id, _} = Integer.parse(id)

  #   updated_markers =
  #     Enum.map(socket.assigns.markers, fn m ->
  #       case m.id do
  #         ^id ->
  #           Map.update(m, :is_disabled, m.is_disabled, &(!&1))

  #         _ ->
  #           m
  #       end
  #     end)

  #   {:ok, assign(socket, markers: updated_markers)}
  # end

  def map_icon(false) do
    # heroicon location-marker
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
      <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd" />
    </svg>
    """
  end

  def map_icon(_) do
    """
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
    """
  end

  defp show_place_things("intents", socket) do
    fetch_place_things([preload: :at_location], socket) |> mark_places(socket)
  end

  defp show_place_things(id, socket) when is_binary(id) do
    fetch_place_things([at_location_id: id], socket) |> mark_places(socket)
  end

  defp show_place_things(
         polygon,
         socket
       ) do
    polygon = Enum.map(polygon, &Map.values(&1))
    polygon = Enum.map(polygon, &{List.first(&1), List.last(&1)})
    polygon = polygon ++ [List.first(polygon)]

    IO.inspect(polygon)

    geom = %Geo.Polygon{
      coordinates: [polygon],
      srid: @postgis_srid
    }

    IO.inspect(geom)

    fetch_place_things([location_within: geom], socket) |> mark_places(socket)
  end

  defp mark_places(places, place \\ nil, socket) when is_list(places) do
    IO.inspect(places)
    place = if (length(places)==1), do: hd(place)

    points = Enum.map(places, &[Map.get(&1, :lat, 0), Map.get(&1, :long, 0)])
    IO.inspect(points)

    {:ok,
     assign(socket,
       markers: places,
       points: points,
       place: place
     )}
  end

  defp mark_places(_, place, socket) do
    {:ok,
     assign(socket,
       place: place
     )}
  end
end
