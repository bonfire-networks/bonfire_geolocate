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

  # YugabyteDB doesn't ship PostGIS, so geolocation is unavailable there
  # TODO: support it with a YugabyteDB image that has PostGIS built in, see https://github.com/giovannicandido/yugabytedb-postgis
  defp postgis_unavailable?, do: System.get_env("DB_ADAPTER") == "yugabyte"

  def change do
    if postgis_unavailable?(),
      do: IO.warn("Skipping geolocation tables since PostGIS isn't currently available on YugabyteDB"),
      else: do_change()
  end

  defp do_change do
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
    if not postgis_unavailable?() do
      create_index_for_pointer(@table, :context_id)
      create_index_for_pointer(@table, :creator_id)
    end
  end
end
