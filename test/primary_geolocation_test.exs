defmodule Bonfire.Geolocate.PrimaryGeolocationTest do
  @moduledoc "The main location of any object, held as a mixin pointing at a Geolocation."
  # `@moduletag :backend` comes with this case
  use Bonfire.Geolocate.DataCase, async: true

  import Bonfire.Me.Fake
  import Bonfire.Geolocate.Simulate
  alias Bonfire.Common.Repo

  test "an object's main location is stored and read back with its geolocation" do
    user = fake_user!()
    geolocation = fake_geolocation!(user)

    assert {:ok, primary} =
             %Bonfire.Geolocate.PrimaryGeolocation{id: user.id}
             |> Bonfire.Geolocate.PrimaryGeolocation.changeset(%{geolocation_id: geolocation.id})
             |> Repo.insert()

    assert %{geolocation: %{id: geolocation_id}} = Repo.maybe_preload(primary, :geolocation)
    assert geolocation_id == geolocation.id
  end

  test "is refused without a geolocation" do
    user = fake_user!()

    refute Bonfire.Geolocate.PrimaryGeolocation.changeset(
             %Bonfire.Geolocate.PrimaryGeolocation{id: user.id},
             %{}
           ).valid?
  end
end
