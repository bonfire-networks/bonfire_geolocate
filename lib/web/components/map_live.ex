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

  @doc "Whether a map given no places nor markers shows some places anyway. Off for a map of a list that can be empty (eg. the events map), which then is an empty map."
  prop fallback_places, :boolean, default: true

  @doc "Whether the map tells its page (the LiveView it is in) the box in view, instead of loading places itself: the page gets `{Bonfire.Geolocate.MapLive, :bounds, %{south: .., west: .., north: .., east: ..}}` (degrees, west and east possibly past 180) once the user has moved the map, not when it loads, and loads what it shows for it."
  prop bounds_to_parent, :boolean, default: false

  @doc "The view to open on, `[[south, west], [north, east]]`, where the map would otherwise be fitted to its markers."
  prop fit_bounds, :list, default: nil
  @doc "The map's size, eg. `h-full` to fill the box it is in."
  prop class, :css_class, default: "min-h-[250px]"

  data maps_enabled, :boolean, default: false
  data signed_in, :boolean, default: false

  # @doc "Whether maps can be drawn: the extension is enabled and the instance has a key for the map tiles (`MAPBOX_API_KEY`, which the map's JS reads too)."
  # def maps_enabled? do
  #   require Bonfire.Common.Config
  #
  #   module_enabled?(Bonfire.Geolocate) and
  #     Bonfire.Common.Config.get([:js_config, :mapbox_api_key], nil, :bonfire) not in [nil, ""]
  # end
  @doc "Whether maps can be drawn: the extension is enabled, and the maps backend (`maps_backend/0`) has what it needs: a key for Mapbox's tiles (`MAPBOX_API_KEY`, which the map's JS reads too), or a server of map styles (`map_styles_url/0`)."
  def maps_enabled? do
    require Bonfire.Common.Config

    module_enabled?(Bonfire.Geolocate) and
      case maps_backend() do
        :mapbox ->
          Bonfire.Common.Config.get([:js_config, :mapbox_api_key], nil, :bonfire) not in [nil, ""]

        :openfreemap ->
          map_styles_url() not in [nil, ""]

        _ ->
          false
      end
  end

  @doc "The maps backend (`MAPS_BACKEND`, see `Bonfire.Geolocate.RuntimeConfig.maps_backend/2`): `:openfreemap` (a server of map styles), `:mapbox` or `:none`."
  def maps_backend do
    require Bonfire.Common.Config
    Bonfire.Common.Config.get([Bonfire.Geolocate, :maps_backend], :openfreemap)
  end

  @doc "The server of the map styles (`MAP_STYLES_URL`, OpenFreeMap's by default), which a style's name is appended to."
  def map_styles_url do
    require Bonfire.Common.Config
    Bonfire.Common.Config.get([Bonfire.Geolocate, :map_styles_url], nil)
  end

  @doc "The map styles offered (in config), as `name: label`."
  def map_styles do
    require Bonfire.Common.Config
    Bonfire.Common.Config.get([Bonfire.Geolocate, :map_styles], [])
  end

  @doc "The URL of the map style for the current user (their setting, else the instance's, else the default in config): a style's name on the styles' server, or a style given as a full URL as it is. Nil without a styles' server."
  def map_style_url(context) do
    # only the `openfreemap` backend draws a map style (Mapbox's are its raster tiles)
    if maps_backend() == :openfreemap, do: do_map_style_url(context)
  end

  defp do_map_style_url(context) do
    style =
      Bonfire.Common.Settings.get([Bonfire.Geolocate, :map_style], "liberty", context)
      |> to_string()

    base = map_styles_url()

    cond do
      String.starts_with?(style, ["https://", "http://"]) -> style
      base in [nil, ""] -> nil
      true -> base <> style
    end
  end

  # read once per map, not per render
  def mount(socket), do: {:ok, assign(socket, maps_enabled: maps_enabled?())}

  # maps are for signed-in users: guests have no LiveView socket, so the map's hook never runs for them
  def update(assigns, socket) do
    signed_in? =
      !!current_user_id(assigns[:__context__] || socket.assigns[:__context__])

    do_update(assigns, assign(socket, signed_in: signed_in?))
  end

  # for a guest, nothing is loaded, and the template asks them to sign in
  defp do_update(assigns, %{assigns: %{signed_in: false}} = socket),
    do: {:ok, assign(socket, assigns)}

  # with no map to draw, nothing is loaded for it, and the template says maps are not set up
  defp do_update(assigns, %{assigns: %{maps_enabled: false}} = socket),
    do: {:ok, assign(socket, assigns)}

  defp do_update(%{places: places} = assigns, socket)
       when is_list(places) and length(places) > 0 do
    mark_places(places, assign(socket, assigns))
  end

  defp do_update(%{place: %{} = place} = assigns, socket) do
    mark_places([place], assign(socket, assigns))
  end

  # markers given by the caller (eg. the events map, with its own popups), before the `id` clause: a stateful component always has an `id`, so the `markers` clause below was never reached
  # def update(%{markers: markers} = assigns, socket)
  #     when is_list(markers) and length(markers) > 0 do
  #   response(assign(socket, assigns), false)
  # end
  # with `points` from the markers, as the map's JS fits its view to `points` (and has no view without them)
  defp do_update(%{markers: markers} = assigns, socket)
       when is_list(markers) and length(markers) > 0 do
    response(assign(socket, assigns) |> assign(points: marker_points(markers)), false)
  end

  # nothing to show, and no other places wanted: an empty map
  defp do_update(%{fallback_places: false} = assigns, socket) do
    response(assign(socket, assigns) |> assign(points: marker_points(assigns[:markers])), false)
  end

  defp do_update(%{id: id} = assigns, socket) when is_binary(id) do
    if id = Types.uid(id) do
      show_place_things(id, assign(socket, assigns))
    else
      assign_default_places(assigns, socket)
    end
  end

  # (moved above the `id` clause)
  # def update(%{markers: markers} = assigns, socket)
  #     when is_list(markers) and length(markers) > 0 do
  #   response(
  #     socket
  #     |> assign(assigns),
  #     false
  #   )
  # end

  defp do_update(assigns, socket) do
    assign_default_places(assigns, socket)
  end

  defp marker_points(markers) do
    for %{lat: lat, long: long} when is_number(lat) and is_number(long) <- List.wrap(markers),
        do: [lat, long]
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
    # do_handle_event(
    #   event,
    #   params,
    #   socket
    # )
    # `true`, for `{:noreply, socket}`, as an event's handler returns (the default, `{:ok, socket}`, is what `update/2` returns)
    do_handle_event(
      event,
      params,
      socket,
      true
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

  # def do_handle_event(
  #       "map_bounds",
  #       polygon,
  #       socket,
  #       to_view
  #     ) do
  #   debug(polygon, "bounds")
  #
  #   show_place_things(Enum.at(polygon, 0), socket, to_view)
  # end
  # the hook sends the map's bounds as a polygon's rings (Leaflet's `_latlngs`), under `bounds`, as event params are a map
  def do_handle_event(
        "map_bounds",
        %{"bounds" => [ring | _]},
        socket,
        to_view
      ) do
    debug(ring, "bounds")

    show_place_things(ring, socket, to_view)
  end

  # the hook sends the box in view as numbers, once the user has moved a map with `bounds_to_parent`: handed to the page (this component runs in its process), which loads what it shows for it. Anything that is not a box is left alone
  def do_handle_event("map_moved", params, socket, to_view) do
    with true <- socket.assigns[:bounds_to_parent] == true,
         %{} = bounds <- bounds_box(params) do
      send(self(), {__MODULE__, :bounds, bounds})
    else
      _ -> debug(params, "map bounds not passed on")
    end

    response(socket, to_view)
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

  # a box from the hook's params: numbers for each side, the south not north of the north and the west not east of the east
  defp bounds_box(%{"south" => south, "west" => west, "north" => north, "east" => east})
       when is_number(south) and is_number(west) and is_number(north) and is_number(east) and
              south <= north and west <= east,
       do: %{south: south / 1, west: west / 1, north: north / 1, east: east / 1}

  defp bounds_box(_), do: nil

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
    # polygon = Enum.map(polygon, &Map.values(&1))
    # polygon = Enum.map(polygon, &{List.first(&1), List.last(&1)})
    # longitude first, as points are stored (`Bonfire.Geolocate.Geolocation`)
    polygon = Enum.map(polygon, &{&1["lng"], &1["lat"]})
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

    # place = if markers && length(markers) == 1, do: hd(markers)
    # a lone place is shown with its activity (unless `show_activity` is off), which needs `peered` (for its URL: the character's, else the place's own); loaded only then, as a list of places shows none
    place =
      if markers && length(markers) == 1 do
        if Map.get(assigns(socket), :show_activity, true),
          do: Bonfire.Common.Repo.maybe_preload(hd(markers), [:peered, character: [:peered]]),
          else: hd(markers)
      end

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
  # positions are stored longitude first (as `Geo`, GeoJSON and PostGIS have them), while Leaflet takes `[lat, lng]`
  defp process_geometries(markers) do
    Enum.reduce(markers, {[], [], [], []}, fn marker, {points, lines, polygons, multi_polygons} ->
      case marker do
        %{geom: %Geo.Point{coordinates: coords}} ->
          # {[[elem(coords, 0), elem(coords, 1)] | points], lines, polygons, multi_polygons}
          {[[elem(coords, 1), elem(coords, 0)] | points], lines, polygons, multi_polygons}

        %{geom: %Geo.LineString{coordinates: coords}} ->
          # line_coords = Enum.map(coords, fn {lat, long} -> [lat, long] end)
          line_coords = Enum.map(coords, &leaflet_pair/1)
          {points, [line_coords | lines], polygons, multi_polygons}

        %{geom: %Geo.Polygon{coordinates: [outer_ring | holes]}} ->
          # outer = Enum.map(outer_ring, fn {lat, long} -> [lat, long] end)
          outer = Enum.map(outer_ring, &leaflet_pair/1)

          holes_formatted =
            Enum.map(holes || [], fn ring ->
              # Enum.map(ring, fn {lat, long} -> [lat, long] end)
              Enum.map(ring, &leaflet_pair/1)
            end)

          polygon = [outer | holes_formatted]
          {points, lines, [polygon | polygons], multi_polygons}

        %{geom: %Geo.MultiPolygon{coordinates: multi_poly_coords}} ->
          formatted_multi_poly =
            Enum.map(multi_poly_coords, fn polygon ->
              Enum.map(polygon, fn ring ->
                # Enum.map(ring, fn {lat, long} -> [lat, long] end)
                Enum.map(ring, &leaflet_pair/1)
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

  # a stored position (longitude first) as Leaflet's `[lat, lng]`
  defp leaflet_pair({long, lat}), do: [lat, long]
  defp leaflet_pair({long, lat, _alt}), do: [lat, long]

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
