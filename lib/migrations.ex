defmodule Bonfire.Geolocate.Migrations do
  use Ecto.Migration
  # alias CommonsPub.Repo
  # alias Pointers.ULID
  import Pointers.Migration

  @user Application.compile_env!(:bonfire, :user_schema)
  # def users_table(), do: @user.__schema__(:source)

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

      add(:context_id, weak_pointer(), null: true)

      add(:creator_id, weak_pointer(), null: true)

      add(:published_at, :timestamptz)
      add(:deleted_at, :timestamptz)
      add(:disabled_at, :timestamptz)

      timestamps(inserted_at: false, type: :utc_datetime_usec)
    end

    # require Bonfire.Geolocate.PrimaryGeolocation.Migration
    # Bonfire.Geolocate.PrimaryGeolocation.Migration.migrate_primary_geolocation()
  end
end
