defmodule Bonfire.Geolocate.Web.GenericMapLive do
  use Bonfire.UI.Common.Web, :live_view

  declare_extension("Maps", icon: "twemoji:world-map")

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, session, socket) do
    {:ok,
     assign(
       socket,
       page_title: "Map",
       page: "map",
       selected_tab: "map",
       showing_within: :map

       # places: fetch_places(socket),
     )}
  end

  # proxy relevent events to the map component # FIXME
  def do_handle_event("map_" <> _action = event, params, socket) do
    debug(proxy_event: event)
    debug(proxy_params: params)
    Bonfire.Geolocate.MapLive.handle_event(event, params, socket, true)
  end

  defdelegate handle_params(params, attrs, socket),
    to: Bonfire.UI.Common.LiveHandlers

  def handle_event(
        action,
        attrs,
        socket
      ),
      do:
        Bonfire.UI.Common.LiveHandlers.handle_event(
          action,
          attrs,
          socket,
          __MODULE__,
          &do_handle_event/3
        )

  def handle_info(info, socket),
    do: Bonfire.UI.Common.LiveHandlers.handle_info(info, socket, __MODULE__)
end
