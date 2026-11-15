defmodule Bonfire.Geolocate.ThingAddLocationTest do
  @moduledoc """
  Adding a location to a thing (`Geolocations.thing_add_location/3`) is checked as the person adding it: whoever the thing is (their own profile) may, anyone else needs the `:tag` permission on it, and without a person it is refused, even when there is no thing either.
  """
  use Bonfire.Geolocate.DataCase, async: false

  import Bonfire.Me.Fake
  alias Bonfire.Geolocate.Geolocations

  setup do
    :meck.new(Bonfire.Geolocate.Geocode, [:passthrough, :no_link])
    :meck.expect(Bonfire.Geolocate.Geocode, :coordinates, fn _query -> {:error, nil} end)
    on_exit(fn -> :meck.unload(Bonfire.Geolocate.Geocode) end)

    :ok
  end

  test "someone may set their own location" do
    me = fake_user!()

    assert {:ok, _} = Geolocations.thing_add_location(me, me, "Home Town")
  end

  test "someone may not set another person's location" do
    me = fake_user!()
    other = fake_user!()

    assert {:error, _} = Geolocations.thing_add_location(me, other, "Their Town")
  end

  test "with no person acting, nothing is tagged, even with no thing either (nil is not the owner of nil)" do
    assert {:error, _} = Geolocations.thing_add_location(nil, nil, "Nowhere")
  end
end
