defmodule Bonfire.Geolocate.Repo.Migrations.AddGeolocateIndexes do
  @moduledoc false
use Ecto.Migration 
  use Needle.Migration.Indexable

  def up do
    Bonfire.Geolocate.Migrations.add_geolocation_indexes()
  end

  def down, do: nil
end
