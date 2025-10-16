defmodule Bonfire.Geolocate.Migrations do
  @moduledoc false
  use Ecto.Migration
  # alias CommonsPub.Repo
  # alias Needle.ULID
  import Needle.Migration
  use Needle.Migration.Indexable

  @user Application.compile_env!(:bonfire, :user_schema)
  # def users_table(), do: @user.__schema__(:source)
  @table Bonfire.Geolocate.Geolocation.__schema__(:source)

  def change do
    :ok =
      execute(
        "create extension IF NOT EXISTS postgis;",
        "drop extension postgis;"
      )

    create_pointable_table(Bonfire.Geolocate.Geolocation) do
      add(:name, :string)
      add(:note, :text)
      add(:mappable_address, :string)
      add(:geom, :geometry)
      add(:alt, :float)
      add_pointer(:context_id, :weak, Needle.Pointer, null: true)
      add_pointer(:creator_id, :weak, Needle.Pointer, null: true)
      add(:published_at, :timestamptz)
      add(:deleted_at, :timestamptz)
      add(:disabled_at, :timestamptz)

      timestamps(inserted_at: false, type: :utc_datetime_usec)
    end

    add_geolocation_indexes()

    # require Bonfire.Geolocate.PrimaryGeolocation.Migration
    # Bonfire.Geolocate.PrimaryGeolocation.Migration.migrate_primary_geolocation()
  end

  def add_geolocation_indexes do
    create_index_for_pointer(@table, :context_id)
    create_index_for_pointer(@table, :creator_id)
  end
end
