# defmodule Bonfire.Geolocate.PrimaryGeolocation do
#   @moduledoc """
#   A mixin for objects (eg profile, post, organisation) to define their main location
#   """
#   use Pointers.Mixin,
#     otp_app: :bonfire_geolocate,
#     source: "bonfire_geolocate_primary_geolocation"

#   alias Bonfire.Geolocate.PrimaryGeolocation
#   alias Ecto.Changeset
#   alias Pointers.Pointer

#   mixin_schema do
#     belongs_to :geolocation, Bonfire.Geolocate.Geolocation
#   end

#   @cast [:geolocation_id]
#   @required [:geolocation_id]

#   def changeset(primary_geolocation \\ %PrimaryGeolocation{}, attrs) do
#     primary_geolocation
#     |> Changeset.cast(attrs, @cast)
#     |> Changeset.validate_required(@required)
#     |> Changeset.assoc_constraint(:geolocation)
#   end
# end

# defmodule Bonfire.Geolocate.PrimaryGeolocation.Migration do
#   use Ecto.Migration
#   import Pointers.Migration
#   alias Bonfire.Geolocate.PrimaryGeolocation

#   # create_primary_geolocation_table/{0, 1}

#   defp make_primary_geolocation_table(exprs) do
#     quote do
#       require Pointers.Migration
#       Pointers.Migration.create_mixin_table(Bonfire.Geolocate.PrimaryGeolocation) do
#         Ecto.Migration.add :geolocation_id, Pointers.Migration.strong_pointer(Bonfire.Geolocate.Geolocation)
#         unquote_splicing(exprs)
#       end
#     end
#   end

#   defmacro create_primary_geolocation_table(), do: make_primary_geolocation_table([])
#   defmacro create_primary_geolocation_table([do: {_, _, body}]), do: make_primary_geolocation_table(body)

#   # drop_primary_geolocation_table/0

#   def drop_primary_geolocation_table(), do: drop_mixin_table(PrimaryGeolocation)

#   # migrate_primary_geolocation/{0, 1}

#   defp mpl(:up), do: make_primary_geolocation_table([])

#   defp mpl(:down) do
#     quote do
#       Bonfire.Geolocate.PrimaryGeolocation.Migration.drop_primary_geolocation_table()
#     end
#   end

#   defmacro migrate_primary_geolocation() do
#     quote do
#       if Ecto.Migration.direction() == :up,
#         do: unquote(mpl(:up)),
#         else: unquote(mpl(:down))
#     end
#   end

#   defmacro migrate_primary_geolocation(dir), do: mpl(dir)

# end
