defmodule Bonfire.Geolocate.Repo.Migrations.AddGeolocationMappableAddressIndex do
  @moduledoc false
  # serves the lookup of a place already saved with the same address (`known_coordinates/1`), which matches on `lower(trim(mappable_address))` among the places with a point, so the index is on that expression and has the same predicate (an index on `mappable_address` itself wouldn't be used)
  use Ecto.Migration

  # YugabyteDB doesn't ship PostGIS, so the geolocation table does not exist there
  def up do
    if System.get_env("DB_ADAPTER") != "yugabyte" do
      execute(
        "CREATE INDEX IF NOT EXISTS bonfire_geolocate_geolocation_mappable_address_index ON bonfire_geolocate_geolocation ((lower(trim(mappable_address)))) WHERE geom IS NOT NULL"
      )
    end
  end

  def down do
    if System.get_env("DB_ADAPTER") != "yugabyte" do
      execute("DROP INDEX IF EXISTS bonfire_geolocate_geolocation_mappable_address_index")
    end
  end
end
