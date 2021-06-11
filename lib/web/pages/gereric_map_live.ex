defmodule Bonfire.Geolocate.Web.GenericMapLive do
  use Bonfire.Web, :live_view

  alias Bonfire.Web.LivePlugs

  def mount(params, session, socket) do
    LivePlugs.live_plug params, session, socket, [
      LivePlugs.LoadCurrentAccount,
      LivePlugs.LoadCurrentUser,
      LivePlugs.StaticChanged,
      LivePlugs.Csrf, LivePlugs.Locale,
      &mounted/3,
    ]
  end

  defp mounted(params, session, socket) do

    {:ok, socket
    |> assign(
      page_title: "Map",
      page: "map",
      selected_tab: "map",
      # places: fetch_places(socket),
    )}
  end


  # proxy relevent events to the map component # FIXME
  def handle_event("map_"<>_action = event, params, socket) do
    IO.inspect(proxy_event: event)
    IO.inspect(proxy_params: params)
    Bonfire.Geolocate.MapLive.handle_event(event, params, socket, true)
  end

  defdelegate handle_params(params, attrs, socket), to: Bonfire.Common.LiveHandlers
  def handle_event(action, attrs, socket), do: Bonfire.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)
  def handle_info(info, socket), do: Bonfire.Common.LiveHandlers.handle_info(info, socket, __MODULE__)

end
