defmodule Bonfire.Geolocate.PrimaryGeolocationsTest do
  @moduledoc "Setting, replacing and removing the main location of an object."
  # `@moduletag :backend` comes with this case
  use Bonfire.Geolocate.DataCase, async: true

  import Bonfire.Me.Fake
  import Bonfire.Geolocate.Simulate
  alias Bonfire.Common.Repo
  alias Bonfire.Geolocate.PrimaryGeolocation
  alias Bonfire.Geolocate.PrimaryGeolocations

  defp main_location_id(object) do
    case Repo.get(PrimaryGeolocation, object.id) do
      %{geolocation_id: id} -> id
      nil -> nil
    end
  end

  test "sets the main location of an object" do
    user = fake_user!()
    geolocation = fake_geolocation!(user)

    assert {:ok, _} = PrimaryGeolocations.set(user, geolocation)
    assert main_location_id(user) == geolocation.id
  end

  test "setting it again replaces it, and keeps one row" do
    user = fake_user!()
    first = fake_geolocation!(user)
    second = fake_geolocation!(user)

    assert {:ok, _} = PrimaryGeolocations.set(user, first)
    assert {:ok, _} = PrimaryGeolocations.set(user, second)

    assert main_location_id(user) == second.id
  end

  test "removes the main location, and leaves the geolocation" do
    user = fake_user!()
    geolocation = fake_geolocation!(user)
    {:ok, _} = PrimaryGeolocations.set(user, geolocation)

    assert {:ok, _} = PrimaryGeolocations.remove(user)

    assert main_location_id(user) == nil
    assert Repo.get(Bonfire.Geolocate.Geolocation, geolocation.id)
  end
end
