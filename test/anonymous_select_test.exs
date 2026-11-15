defmodule Bonfire.Geolocate.AnonymousSelectTest do
  @moduledoc """
  Choosing a location that does not exist yet creates it, and the address is geocoded by an external service. Only a signed-in user may cause that: a visitor without a session who sends a free-text name through the plain `/LiveHandler` route must leave no place behind and must not trigger any geocoding request.

  The geocoding step is replaced by a recorder, so the tests check how often it was asked. A test where a signed-in user creates the place and the geocoder is asked shows the recorder works.
  """
  use Bonfire.Geolocate.ConnCase, async: false

  import Ecto.Query
  alias Bonfire.Geolocate.Geolocation

  setup do
    :meck.new(Bonfire.Geolocate.Geocode, [:passthrough, :no_link])
    :meck.expect(Bonfire.Geolocate.Geocode, :coordinates, fn _query -> {:error, nil} end)
    on_exit(fn -> :meck.unload(Bonfire.Geolocate.Geocode) end)

    {:ok, name: "Anon Place #{System.unique_integer([:positive])}"}
  end

  defp place_exists?(name),
    do: Bonfire.Common.Config.repo().exists?(from(g in Geolocation, where: g.name == ^name))

  test "a signed-in user's free-text choice creates the place and geocodes it (control)", %{
    name: name
  } do
    assert {^name, id} =
             Bonfire.Geolocate.LiveHandler.create_in_autocomplete(fake_user!(), name)

    assert is_binary(id)
    assert place_exists?(name)
    assert :meck.num_calls(Bonfire.Geolocate.Geocode, :coordinates, :_) == 1
  end

  test "a visitor without a session creates no place and triggers no geocoding", %{name: name} do
    get(
      build_conn(),
      "/LiveHandler/Bonfire.Geolocate/select?" <>
        URI.encode_query(%{"id" => name, "name" => name})
    )

    refute place_exists?(name)
    assert :meck.num_calls(Bonfire.Geolocate.Geocode, :coordinates, :_) == 0
  end
end
