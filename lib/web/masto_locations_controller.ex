if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Geolocate.Web.MastoLocationsController do
    @moduledoc "Mastodon-compatible locations REST endpoints."

    use Bonfire.UI.Common.Web, :controller
    import Untangle

    alias Bonfire.Geolocate.API.GraphQLMasto.LocationsAdapter

    def index(conn, params) do
      debug(params, "GET /api/v1/locations")
      locations = LocationsAdapter.list_locations(params, conn)
      json(conn, locations)
    end

    def show(conn, %{"id" => id}) do
      debug(id, "GET /api/v1/locations/:id")

      case LocationsAdapter.get_location(id, conn) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{"error" => "Location not found"})

        location ->
          json(conn, location)
      end
    end
  end
end
