defmodule Bonfire.Geolocate.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler

  # alias Bonfire.Geolocate.Geolocation
  alias Bonfire.Geolocate.Geolocations

  def handle_event("create", attrs, socket) do
    with {:ok, geolocation} <- Geolocations.create(current_user_required!(socket), attrs) do
      debug(created_geolocation: geolocation)

      {:noreply,
       redirect_to(
         socket,
         e(attrs, "redirect_after", ~p"/geolocation") <> "/" <> geolocation.id
       )}
    end
  end

  def handle_event("autocomplete", %{"value" => search}, socket),
    do: handle_event("autocomplete", search, socket)

  def handle_event("autocomplete", search, socket) when is_binary(search) do
    # debug(search: search)

    options =
      (Geolocations.search(search) || [])
      |> Enum.map(&to_tuple/1)

    options =
      options ++
        [{"Define a new location with this address: " <> search, search}]

    {:noreply, assign_global(socket, geolocation_autocomplete: options)}
  end

  def handle_event(
        "select",
        %{"id" => select_geolocation, "name" => name} = _attrs,
        socket
      )
      when is_binary(select_geolocation) do
    # debug(socket)

    selected =
      if !is_uid?(select_geolocation),
        do: create_in_autocomplete(current_user(socket), select_geolocation),
        else: {name, select_geolocation}

    debug(selected)
    {:noreply, assign_global(socket, geolocation_selected: [selected])}
  end

  # --- the feed filters editor's Nearby control (`Bonfire.Geolocate.FeedFilterNearbyLive`) ---
  # Its events are prefixed with this extension's name and target the editor, so they arrive here with the editor's own socket. The editor's pending filters are changed through `put_pending/2`, and what the control keeps between events is in the socket's `control_state`. No guest events are declared, so a guest is refused before reaching these.

  alias Bonfire.Geolocate.FeedFilterNearbyLive, as: Nearby
  alias Bonfire.Geolocate.ViewerLocation

  # the row was opened and the setting has no coordinates: try the profile's location text, once. A geocoded point is kept in the user's own location setting (rounded), with the profile's text as its name, so it isn't geocoded again; the profile is never written
  def handle_event("locate", _params, socket) do
    context = socket.assigns[:__context__]

    if e(socket.assigns, :control_state, :nearby, :checked?, false) or
         not is_nil(Nearby.viewer_location(context)) do
      {:noreply, socket}
    else
      geocode = socket.assigns[:geocode] || (&Bonfire.Geolocate.Geocode.coordinates/1)

      case ViewerLocation.resolve(context, geocode: geocode) do
        %{source: :profile, lat: lat, long: long, name: name} ->
          ViewerLocation.save(context, lat, long, name)

        _ ->
          nil
      end

      {:noreply, put_control_state(socket, %{checked?: true})}
    end
  end

  # the browser's location, sent by the "Detect location" button's hook: saved with its place name to the user's location setting (never to the profile), and the filter is turned on
  def handle_event("set_location", %{"lat" => lat, "long" => long}, socket) do
    context = socket.assigns[:__context__]

    reverse_geocode =
      socket.assigns[:reverse_geocode] || (&Bonfire.Geolocate.Geocode.place_name/2)

    with lat when is_number(lat) <- to_float(lat),
         long when is_number(long) <- to_float(long),
         lat = Float.round(lat, 3),
         long = Float.round(long, 3),
         {:ok, %{lat: lat, long: long}} <-
           ViewerLocation.save(context, lat, long, reverse_geocode.(lat, long)) do
      {:noreply,
       socket
       |> put_control_state(%{place: nil, place_not_found: false})
       |> put_nearby(%{lat: lat, long: long}, %{})}
    else
      other ->
        debug(other, "no usable location")
        {:noreply, socket}
    end
  end

  # the radius (in the viewer's units) and whether things with no place are included; an empty radius turns it off (explicitly nil, as the host merges what's applied into the filters it has). Needs a location
  def handle_event("set_nearby", params, socket) do
    point = nearby_point(socket)

    cond do
      is_nil(point) ->
        {:noreply, socket}

      params["radius"] in [nil, ""] and Map.has_key?(params, "radius") ->
        {:noreply, put_pending(socket, %{nearby: nil})}

      true ->
        {:noreply, put_nearby(socket, point, params)}
    end
  end

  # a place typed in the row, used for this search only (the saved location stays as it is); emptied, it goes back to the saved location
  def handle_event("set_place", %{"place" => place}, socket) when is_binary(place) do
    context = socket.assigns[:__context__]
    place = String.trim(place)

    cond do
      place == "" ->
        socket = put_control_state(socket, %{place: nil, place_not_found: false})

        case Nearby.viewer_location(context) do
          %{lat: lat, long: long} -> {:noreply, put_nearby(socket, %{lat: lat, long: long}, %{})}
          _ -> {:noreply, socket}
        end

      true ->
        geocode = socket.assigns[:geocode] || (&Bonfire.Geolocate.Geocode.coordinates/1)

        case geocode.(place) do
          {:ok, %{lat: lat, lon: long}} when is_number(lat) and is_number(long) ->
            lat = Float.round(lat / 1, 3)
            long = Float.round(long / 1, 3)

            {:noreply,
             socket
             |> put_control_state(%{
               place: %{name: place, lat: lat, long: long},
               place_not_found: false
             })
             |> put_nearby(%{lat: lat, long: long}, %{})}

          _ ->
            {:noreply, put_control_state(socket, %{place_not_found: true})}
        end
    end
  end

  # the point already on the filter if it has one (a typed place, or a saved feed), else the viewer's location
  defp nearby_point(socket) do
    case e(socket.assigns, :pending_filters, :nearby, nil) do
      %{lat: lat, long: long} ->
        %{lat: lat, long: long}

      _ ->
        case Nearby.viewer_location(socket.assigns[:__context__]) do
          %{lat: lat, long: long} -> %{lat: lat, long: long}
          _ -> nil
        end
    end
  end

  defp put_nearby(socket, point, params) do
    units = Nearby.units(socket.assigns[:__context__])
    previous = e(socket.assigns, :pending_filters, :nearby, nil)
    put_pending(socket, %{nearby: nearby_filter(point, previous, params, units)})
  end

  # a new radius, or the one set before, else 25 km; things with no place are in unless asked
  defp nearby_filter(%{lat: lat, long: long}, previous, params, units) do
    previous = if is_map(previous), do: previous, else: %{}

    km =
      case params["radius"] && Types.maybe_to_integer(params["radius"]) do
        radius when is_integer(radius) and radius > 0 -> Nearby.to_km(radius, units)
        _ -> previous[:km] || 25
      end

    include_no_place =
      case params["include_no_place"] do
        "true" -> true
        "false" -> false
        _ -> Map.get(previous, :include_no_place, true)
      end

    %{lat: lat, long: long, km: km, include_no_place: include_no_place}
  end

  # `Bonfire.UI.Social` is not a dependency of this extension, but the editor that renders the control is part of it
  defp put_pending(socket, patch) do
    maybe_apply(Bonfire.UI.Social.FeedFiltersModalContentLive, :put_pending, [socket, patch],
      fallback_return: socket
    )
  end

  defp put_control_state(socket, patch) do
    state = socket.assigns[:control_state] || %{}
    nearby = Map.merge(state[:nearby] || %{}, patch)
    assign(socket, :control_state, Map.put(state, :nearby, nearby))
  end

  defp to_float(n) when is_number(n), do: n / 1

  defp to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_float(_), do: nil

  def to_tuple(geolocation) do
    {geolocation.name, geolocation.id}
  end

  def create_in_autocomplete(creator, name) do
    with {:ok, rs} <-
           Geolocations.create(creator, %{name: name, mappable_address: name}) do
      {rs.name, rs.id}
    end
  end
end
