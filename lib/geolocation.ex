defmodule Bonfire.Geolocate.Geolocation do
  use Needle.Pointable,
    otp_app: :bonfire_geolocate,
    source: "bonfire_geolocate_geolocation",
    table_id: "2P1ACEW1THGE0010CAT10NMARK"

  import Bonfire.Common.Repo.Utils, only: [change_public: 1, change_disabled: 1]

  alias Ecto.Changeset
  alias Needle.Pointer
  @user Application.compile_env!(:bonfire, :user_schema)

  @type t :: %__MODULE__{}

  pointable_schema do
    field(:name, :string)

    field(:geom, Geo.PostGIS.Geometry)
    # field(:geom, :map, virtual: true)

    # altitude
    field(:alt, :float)
    field(:mappable_address, :string)
    field(:note, :string)

    field(:lat, :float, virtual: true)
    field(:long, :float, virtual: true)

    field(:is_public, :boolean, virtual: true)
    field(:published_at, :utc_datetime_usec)
    field(:is_disabled, :boolean, virtual: true, default: false)
    field(:disabled_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)

    # FIXME, implement Bonfire Character
    # field(:character, :any, virtual: true)
    # has_one(:character, CommonsPub.Characters.Character, references: :id, foreign_key: :id)

    belongs_to(:creator, @user)

    belongs_to(:context, Pointer)

    # because it's keyed by pointer
    field(:follower_count, :any, virtual: true)

    timestamps(inserted_at: false)
  end

  @postgis_srid 4326

  @required ~w(name)a
  @cast_fallback @required ++ ~w(note mappable_address lat long alt is_disabled)a
  @cast @cast_fallback ++ ~w(geom)a

  def create_changeset(
        creator,
        attrs,
        opts \\ []
      ) do
    %__MODULE__{}
    |> Changeset.cast(attrs, @cast)
    |> Changeset.validate_required(@required)
    |> Changeset.change(
      creator_id: Bonfire.Common.Enums.id(creator),
      context_id: Bonfire.Common.Enums.id(opts[:context]),
      is_public: true
    )
    |> validate_coordinates(opts[:skip_geom])
    |> common_changeset()
  end

  def update_changeset(%__MODULE__{} = geolocation, attrs) do
    geolocation
    |> Changeset.cast(attrs, @cast)
    |> validate_coordinates()
    |> common_changeset()
  end

  defp common_changeset(changeset) do
    changeset
    |> change_public()
    |> change_disabled()
  end

  defp validate_coordinates(changeset, skip_geom? \\ false) do
    lat = Changeset.get_change(changeset, :lat)
    long = Changeset.get_change(changeset, :long)

    if !skip_geom? and not (is_nil(lat) or is_nil(long)) do
      geom = %Geo.Point{coordinates: {lat, long}, srid: @postgis_srid}
      Changeset.change(changeset, geom: geom)
    else
      changeset
    end
  end

  @behaviour Bonfire.Common.SchemaModule
  def context_module, do: Bonfire.Geolocate.Geolocations
  def query_module, do: Bonfire.Geolocate.Queries

  def follow_filters, do: []
end
