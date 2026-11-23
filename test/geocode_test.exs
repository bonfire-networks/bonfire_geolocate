defmodule Bonfire.Geolocate.GeocodeTest do
  @moduledoc "The geocoder's worker pool runs once the app has booted, and a missing pool gives a clear error. No request goes to a real geocoding service."
  use Bonfire.Geolocate.DataCase, async: false

  alias Bonfire.Geolocate.Geocode

  test "the geocoder's worker pool and store are running" do
    assert is_pid(Process.whereis(:geocoder_workers))
    assert is_pid(Process.whereis(:geocoder_store))
  end

  test "coordinates/1 returns a clear error when the pool is not running" do
    :ok = Supervisor.terminate_child(Bonfire.Geolocate.Supervisor, Geocoder.Supervisor)
    on_exit(fn -> Supervisor.restart_child(Bonfire.Geolocate.Supervisor, Geocoder.Supervisor) end)

    assert is_nil(Process.whereis(:geocoder_workers))
    assert {:error, :geocoder_not_running} = Geocode.coordinates("The Mansion, Totnes")
    assert nil == Geocode.place_name(50.43, -3.68)
  end
end
