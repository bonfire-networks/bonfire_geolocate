defmodule Bonfire.Geolocate.LiveHandler do
  use Bonfire.Web, :live_handler

  alias Bonfire.Geolocate.Geolocation
  alias Bonfire.Geolocate.Geolocations

  def handle_event("create", attrs, socket) do
    with {:ok, geolocation} <- Geolocations.create(socket.assigns.current_user, attrs) do
      IO.inspect(created_geolocation: geolocation)
      {:noreply, socket |> push_redirect(to: e(attrs, "redirect_after", "/geolocation/")<>geolocation.id)}
    end
  end


  def handle_event("autocomplete", search, socket) when is_binary(search) do
    IO.inspect(search: search)

    matches = with {:ok, matches} <- Geolocations.many(autocomplete: search) do
      # IO.inspect(matches)
      matches |> Enum.map(&to_tuple/1)
    else
      _ -> []
    end
    # IO.inspect(matches)

    options = matches ++ [{"Define a new location with the address: "<>search, search}]

    {:noreply, socket |> cast_self(geolocation_autocomplete: options) }
  end


  def handle_event("select", %{"id" => select_geolocation, "name"=> name} = attrs, socket) when is_binary(select_geolocation) do
    # IO.inspect(socket)

    selected = if !is_ulid?(select_geolocation), do: create_in_autocomplete(e(socket.assigns, :current_user, nil), select_geolocation), else: {name, select_geolocation}

    IO.inspect(selected)
    {:noreply, socket |> cast_self(geolocation_selected: [selected])}
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
