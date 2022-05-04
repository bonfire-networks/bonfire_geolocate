defmodule Bonfire.Geolocate.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler

  alias Bonfire.Geolocate.Geolocation
  alias Bonfire.Geolocate.Geolocations

  def handle_event("create", attrs, socket) do
    with {:ok, geolocation} <- Geolocations.create(current_user(socket), attrs) do
      debug(created_geolocation: geolocation)
      {:noreply, socket |> push_redirect(to: e(attrs, "redirect_after", "/geolocation/")<>geolocation.id)}
    end
  end


  def handle_event("autocomplete", %{"value"=>search}, socket), do: handle_event("autocomplete", search, socket)
  def handle_event("autocomplete", search, socket) when is_binary(search) do
    # debug(search: search)

    options = ( Geolocations.search(search) || [] )
              |> Enum.map(&to_tuple/1)

    options = options ++ [{"Define a new location with this address: "<>search, search}]

    {:noreply, socket |> assign_global(geolocation_autocomplete: options) }
  end


  def handle_event("select", %{"id" => select_geolocation, "name"=> name} = attrs, socket) when is_binary(select_geolocation) do
    # debug(socket)

    selected = if !is_ulid?(select_geolocation), do: create_in_autocomplete(current_user(socket), select_geolocation), else: {name, select_geolocation}

    debug(selected)
    {:noreply, socket |> assign_global(geolocation_selected: [selected])}
  end

  def to_tuple(geolocation) do
    {geolocation.name, geolocation.id}
  end

  def create_in_autocomplete(creator, name) do
    with {:ok, rs} <- Geolocations.create(creator, %{name: name, mappable_address: name}) do
      {rs.name, rs.id}
    end
  end


end
