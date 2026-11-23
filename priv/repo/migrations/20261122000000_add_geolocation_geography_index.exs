defmodule Bonfire.Geolocate.Repo.Migrations.AddGeolocationGeographyIndex do
  @moduledoc false
  # a spatial index for "within a distance of a point" queries (the nearby feed filter, `near_point`), which measure on `geom::geography`, so the index is on that expression (an index on `geom` itself wouldn't be used)
  use Ecto.Migration

  # YugabyteDB doesn't ship PostGIS, so the geolocation table does not exist there
  def up do
    if System.get_env("DB_ADAPTER") != "yugabyte" do
      execute(
        "CREATE INDEX IF NOT EXISTS bonfire_geolocate_geolocation_geom_geography_index ON bonfire_geolocate_geolocation USING GIST ((geom::geography))"
      )
    end
  end

  def down do
    if System.get_env("DB_ADAPTER") != "yugabyte" do
      execute("DROP INDEX IF EXISTS bonfire_geolocate_geolocation_geom_geography_index")
    end
  end
end
