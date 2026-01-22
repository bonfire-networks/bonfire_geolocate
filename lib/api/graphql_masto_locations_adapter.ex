defmodule Bonfire.Geolocate.API.GraphQLMasto.LocationsAdapter do
  @moduledoc """
  Mastodon-compatible Locations API adapter using GraphQL.

  Implements:
  - GET /api/v1/locations
  - GET /api/v1/locations/:id
  """

  use AbsintheClient,
    schema: Bonfire.API.GraphQL.Schema,
    action: [mode: :internal]

  import Untangle

  @location_fields "
  id
  uri: canonicalUrl
  name
  note
  address: mappableAddress
  # lat
  # long
  # alt
  geom
  "

  @doc """
  List locations for Mastodon API.
  """
  @graphql """
  query($limit: Int) {
    spatialThings(limit: $limit) {
      #{@location_fields}
    }
  }
  """
  def list_locations(params, conn) do
    limit = params["limit"] || 10

    case graphql(conn, :list_locations, %{"limit" => limit}) do
      %{data: %{spatialThings: locs}} when is_list(locs) ->
        locs

      other ->
        err(other, "Unexpected response")
        []
    end
  end

  @doc """
  Get a single location for Mastodon API.
  """
  @graphql """
  query($id: ID!) {
    spatialThing(id: $id) {
      #{@location_fields}
    }
  }
  """
  def get_location(id, conn) do
    case graphql(conn, :get_location, %{"id" => id}) do
      %{data: %{spatialThing: loc}} when is_map(loc) ->
        loc

      other ->
        err(other, "Unexpected response")
        nil
    end
  end
end
