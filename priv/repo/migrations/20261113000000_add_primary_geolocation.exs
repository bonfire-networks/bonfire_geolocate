defmodule Bonfire.Geolocate.Repo.Migrations.AddPrimaryGeolocation do
  @moduledoc false
  use Ecto.Migration
  require Bonfire.Geolocate.PrimaryGeolocation.Migration

  # YugabyteDB doesn't ship PostGIS, so the geolocation table this points at does not exist there
  def up do
    if System.get_env("DB_ADAPTER") != "yugabyte" do
      Bonfire.Geolocate.PrimaryGeolocation.Migration.migrate_primary_geolocation(:up)
    end
  end

  def down do
    if System.get_env("DB_ADAPTER") != "yugabyte" do
      Bonfire.Geolocate.PrimaryGeolocation.Migration.migrate_primary_geolocation(:down)
    end
  end
end
