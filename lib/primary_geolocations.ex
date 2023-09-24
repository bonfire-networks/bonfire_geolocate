# # SPDX-License-Identifier: AGPL-3.0-only
# defmodule Bonfire.Geolocate.PrimaryGeolocations do
#   import Bonfire.Common.Config, only: [repo: 0]

# TODO: for adding primary location of a user, etc?

#   alias Bonfire.Geolocate.PrimaryGeolocation

#   ## mutations

#   @doc """
#   Set primary location of an object
#   """
#   def set(object, attrs) when is_map(attrs) do
#     repo().transact_with(fn ->
#       with {:ok, item} <- upsert_geolocation(object, attrs),
#            {:ok, character} <- {:ok, nil} # FIXME: Characters.create(creator, attrs, item)
#            do
#         {:ok, item}
#       end
#     end)
#   end

#   defp upsert_geolocation(object, attrs) do
#     cs = PrimaryGeolocation.changeset(object, attrs)
#     with {:ok, item} <- repo().upsert(cs, attrs), do: {:ok, item}
#   end

#   def soft_delete(%{} = user, %PrimaryGeolocation{} = geo) do
#     repo().transact_with(fn ->
#       with {:ok, geo} <- Bonfire.Common.Repo.Delete.soft_delete(geo) do
#         {:ok, geo}
#       end
#     end)
#   end

#   def soft_delete(%{} = user, %{id: id}) do
#     soft_delete(id, user)
#   end

#   import Ecto.Query
#   def soft_delete(%{} = user, id) when is_binary(id) do
#     with {:ok, geo} <- repo().single(from pg in PrimaryGeolocation, where: pg.id == ^id) do
#       soft_delete(geo, user)
#     end
#   end
# end
