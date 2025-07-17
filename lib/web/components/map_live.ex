defmodule Bonfire.Geolocate.MapLive do
  use Bonfire.UI.Common.Web, :stateful_component
  import Bonfire.Geolocate.Places

  @postgis_srid 4326

  prop place, :any, default: nil
  prop places, :list, default: []
  prop markers, :list, default: []
  prop points, :list, default: []
  prop lines, :list, default: []
  prop polygons, :list, default: []
  prop multi_polygons, :list, default: []
  prop show_activity, :boolean, default: true

  def update(%{places: places} = assigns, socket)
      when is_list(places) and length(places) > 0 do
    mark_places(places, assign(socket, assigns))
  end

  def update(%{place: %{} = place} = assigns, socket) do
    mark_places([place], assign(socket, assigns))
  end

  def update(%{id: id} = assigns, socket) when is_binary(id) do
    if id = Types.uid(id) do
      show_place_things(id, assign(socket, assigns))
    else
      assign_default_places(assigns, socket)
    end
  end

  def update(%{markers: markers} = assigns, socket)
      when is_list(markers) and length(markers) > 0 do
    response(
      socket
      |> assign(assigns),
      false
    )
  end

  def update(assigns, socket) do
    assign_default_places(assigns, socket)
  end

  def assign_default_places(assigns, socket) do
    socket = assign(socket, assigns)

    debug("fallback to showing some locations, because no `places` assign was set")

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
    debug(id, "clicked")

    show_place_things(id, socket, to_view)
  end

  def do_handle_event(
        "map_bounds",
        polygon,
        socket,
        to_view
      ) do
    debug(polygon, "bounds")

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

  defp show_place_things(id, socket, to_view \\ false)

  defp show_place_things(id, socket, to_view) when is_binary(id) do
    fetch_place(id, socket)
    |> mark_places(socket, to_view)
  end

  defp show_place_things(
         polygon,
         socket,
         to_view
       ) do
    polygon = Enum.map(polygon, &Map.values(&1))
    polygon = Enum.map(polygon, &{List.first(&1), List.last(&1)})
    polygon = polygon ++ [List.first(polygon)]

    debug(polygon, "polygon")

    geom = %Geo.Polygon{
      coordinates: [polygon],
      srid: @postgis_srid
    }

    debug(geom, "geom")

    fetch_place_things_fn =
      Map.get(assigns(socket), :fetch_place_things_fn, &fetch_place_things/2)

    debug(fetch_place_things_fn, "fetch_place_things_fn")

    apply(fetch_place_things_fn, [[location_within: geom], socket])
    |> mark_places(socket, to_view)
  end

  defp mark_places(places, socket, to_view \\ false)
  defp mark_places(%{edges: places}, socket, to_view), do: mark_places(places, socket, to_view)

  defp mark_places(places, socket, to_view) when is_list(places) do
    markers = Bonfire.Geolocate.Geolocations.populate_coordinates(places)
    IO.inspect(markers, label: "marked_places")

    place = if markers && length(markers) == 1, do: hd(markers)

    # WIP: Extract and process different geometry types
    {points, lines, polygons, multi_polygons} = process_geometries(markers)

    # Deprecated: original points extraction 
    # points =
    #   Enum.map(
    #     markers,
    #     fn marker ->
    #       [
    #         e(marker, :lat, 0),
    #         e(marker, :long, 0)
    #       ]
    #     end
    #   )
    #   |> Enum.filter(fn [h, t] ->
    #     if(h && t && h != 0 && t != 0) do
    #       [h, t]
    #     end
    #   end)

    response(
      assign(
        socket,
        [
          place: place,
          markers: markers,
          points: points,
          lines: lines,
          polygons: polygons,
          multi_polygons: multi_polygons
        ]
        |> debug("map assigns")
      ),
      to_view
    )
  end

  defp mark_places(%{} = place, socket, to_view) do
    mark_places([place], socket, to_view)
  end

  defp mark_places(_, socket, to_view) do
    response(
      socket,
      to_view
    )
  end

  # Process markers to extract different geometry types
  defp process_geometries(markers) do
    Enum.reduce(markers, {[], [], [], []}, fn marker, {points, lines, polygons, multi_polygons} ->
      case marker do
        %{geom: %Geo.Point{coordinates: coords}} ->
          {[[elem(coords, 0), elem(coords, 1)] | points], lines, polygons, multi_polygons}

        %{geom: %Geo.LineString{coordinates: coords}} ->
          line_coords = Enum.map(coords, fn {lat, long} -> [lat, long] end)
          {points, [line_coords | lines], polygons, multi_polygons}

        %{geom: %Geo.Polygon{coordinates: [outer_ring | holes]}} ->
          outer = Enum.map(outer_ring, fn {lat, long} -> [lat, long] end)

          holes_formatted =
            Enum.map(holes || [], fn ring ->
              Enum.map(ring, fn {lat, long} -> [lat, long] end)
            end)

          polygon = [outer | holes_formatted]
          {points, lines, [polygon | polygons], multi_polygons}

        %{geom: %Geo.MultiPolygon{coordinates: multi_poly_coords}} ->
          formatted_multi_poly =
            Enum.map(multi_poly_coords, fn polygon ->
              Enum.map(polygon, fn ring ->
                Enum.map(ring, fn {lat, long} -> [lat, long] end)
              end)
            end)

          {points, lines, polygons, [formatted_multi_poly | multi_polygons]}

        %{lat: lat, long: long}
        when not is_nil(lat) and not is_nil(long) and lat != 0 and long != 0 ->
          {[[lat, long] | points], lines, polygons, multi_polygons}

        _ ->
          {points, lines, polygons, multi_polygons}
      end
    end)
  end

  def response(socket, true) do
    {:noreply, socket}
  end

  def response(socket, _) do
    {:ok, socket}
  end

  def map_icon(false) do
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
