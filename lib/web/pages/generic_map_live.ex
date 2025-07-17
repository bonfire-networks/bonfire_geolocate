defmodule Bonfire.Geolocate.Web.GenericMapLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  declare_extension("Maps",
    icon: "ph:map-pin-fill",
    emoji: "📍",
    description: l("Record locations, make and display maps.")
  )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       page_title: "Map",
       page: "map",
       selected_tab: "map",
       showing_within: :map,
      nav_items: Bonfire.Common.ExtensionModule.default_nav()
       # places: fetch_places(socket),
     )}
  end

  # proxy relevent events to the map component
  def handle_event("map_" <> _action = event, params, socket) do
    debug(event, "event")
    debug(params, "params")
    Bonfire.Geolocate.MapLive.do_handle_event(event, params, socket, true)
  end

  def handle_event(event, params, socket) do
    debug(event, "event")
    debug(params, "params")
    Bonfire.Geolocate.MapLive.do_handle_event(event, params, socket, true)
  end
end
