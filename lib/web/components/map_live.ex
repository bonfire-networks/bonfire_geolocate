defmodule Bonfire.Geolocate.MapLive do
  use Bonfire.UI.Common.Web, :live_component
  import Bonfire.Geolocate.Places

  @postgis_srid 4326

  # attr :place, :any, default: nil

  def update(%{id: id} = assigns, socket) when is_binary(id) do
    show_place_things(id, assign(socket, assigns))
  end

  def update(%{places: places} = assigns, socket)
      when is_list(places) and length(places) > 0 do
    # debug(places: places)
    mark_places(places, assign(socket, assigns))
  end

  def update(%{markers: markers} = assigns, socket)
      when is_list(markers) and length(markers) > 0 do
    response(
      assign_defaults(socket)
      |> assign(assigns),
      false
    )
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    debug("fallback to showing some locations, because no `places` assign was set ")

    fetch_places(socket) |> mark_places(socket)
  end

  def handle_event(
        event,
        params,
        socket
      ) do
    do_handle_event(
      event,
      params,
      socket
    )
  end

  def do_handle_event(
        "map_marker_click",
        %{"id" => id} = _params,
        socket,
        to_view \\ false
      ) do
    debug(click: id)

    show_place_things(id, socket, to_view)
  end

  def do_handle_event(
        "map_bounds",
        polygon,
        socket,
        to_view
      ) do
    debug(bounds: polygon)

    show_place_things(Enum.at(polygon, 0), socket, to_view)
  end

  def do_handle_event(
        "current_location",
        polygon,
        socket,
        to_view
      ) do
    warn("TODO: handle current_location")

    response(socket, to_view)
  end

  # def do_handle_event("map_toggle_marker", %{"id" => id} = _params, socket, to_view ) do
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

  defp show_place_things(id, socket, to_view \\ false) when is_binary(id) do
    # fetch_place_things([at_location_id: id], socket) |> mark_places(socket, to_view)
    fetch_place(id, socket) |> mark_places(socket, to_view)
  end

  # defp show_place_things("intents", socket,
  #       to_view) do
  #   fetch_place_things([preload: :at_location], socket) |> mark_places(socket, to_view)
  # end

  defp show_place_things(
         polygon,
         socket,
         to_view
       ) do
    polygon = Enum.map(polygon, &Map.values(&1))
    polygon = Enum.map(polygon, &{List.first(&1), List.last(&1)})
    polygon = polygon ++ [List.first(polygon)]

    debug(polygon: polygon)

    geom = %Geo.Polygon{
      coordinates: [polygon],
      srid: @postgis_srid
    }

    debug(geom: geom)

    fetch_place_things_fn = Map.get(socket.assigns, :fetch_place_things_fn, &fetch_place_things/2)

    debug(fetch_place_things_fn: fetch_place_things_fn)

    apply(fetch_place_things_fn, [[location_within: geom], socket])
    |> mark_places(socket, to_view)
  end

  defp mark_places(places, socket, to_view \\ false) when is_list(places) do
    markers = Bonfire.Geolocate.Geolocations.populate_coordinates(places)
    debug(markers, "marked_places")

    place = if markers && length(markers) == 1, do: hd(markers)

    # calculation map bounds
    points =
      Enum.map(
        markers,
        &[
          place_lat(&1),
          place_long(&1)
        ]
      )
      |> Enum.filter(fn [h, t] ->
        if(h && t && h != 0 && t != 0) do
          [h, t]
        end
      end)

    # debug(points: points)

    response(
      assign(socket,
        markers: markers,
        points: points,
        place: place
      ),
      to_view
    )
  end

  defp mark_places(%{} = place, socket, to_view) do
    mark_places([place], socket, to_view)
  end

  defp mark_places(_, socket, to_view) do
    response(
      assign_defaults(socket),
      to_view
    )
  end

  defp assign_defaults(socket) do
    socket
    |> assign_new(:place, fn -> nil end)
    |> assign_new(:points, fn -> [] end)
    |> assign_new(:markers, fn -> [] end)
  end

  def place_lat(place) do
    Map.get(place, :lat) ||
      (Map.get(place, :geom) || %{})
      |> Map.get(:coordinates, {0, 0})
      |> elem(0)
  end

  def place_long(place) do
    Map.get(place, :long) ||
      (Map.get(place, :geom) || %{})
      |> Map.get(:coordinates, {0, 0})
      |> elem(1)
  end

  def response(socket, true) do
    {:noreply, socket}
  end

  def response(socket, _) do
    {:ok, socket}
  end

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
end
