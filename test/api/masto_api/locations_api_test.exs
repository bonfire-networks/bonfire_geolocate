# SPDX-License-Identifier: AGPL-3.0-only

defmodule Bonfire.Geolocate.LocationsApiTest do
  @moduledoc """
  Tests for Mastodon-compatible Locations API endpoints.

  Covers:
  - GET /api/v1/locations - List locations
  - GET /api/v1/locations/:id - Get location details
  """

  use Bonfire.Geolocate.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"

  import Bonfire.Me.Fake
  import Bonfire.Geolocate.Simulate
  import Untangle

  @moduletag :masto_api

  describe "GET locations" do
    test "returns a list of locations" do
      user = fake_user!()
      location = fake_geolocation!(user, nil, %{mappable_address: mappable_address()})

      # check it can be fetched
      {:ok, geo} = Bonfire.Geolocate.Geolocations.many()
      location_ids = Enum.map(geo, & &1.id)
      assert location.id in location_ids

      conn = user_conn(user)

      response =
        conn
        |> get("/api/bonfire-v1/locations")
        |> json_response(200)

      flood(response, "Locations response")

      assert is_list(response)
      ids = Enum.map(response, & &1["id"])
      assert location.id in ids
      loc = Enum.find(response, &(&1["id"] == location.id))
      assert_location_fields(loc)
    end
  end

  describe "GET locations/:id" do
    test "returns location details" do
      user = fake_user!()
      location = fake_geolocation!(user, nil, %{mappable_address: fake_mappable_address()})

      # check it was created
      {:ok, _geo} = Bonfire.Geolocate.Geolocations.one(id: location.id)

      conn = user_conn(user)

      response =
        conn
        |> get("/api/bonfire-v1/locations/#{location.id}")
        |> json_response(200)

      flood(response, "Location details response")

      assert_location_fields(response)
      assert response["id"] == location.id
    end
  end

  defp assert_location_fields(loc) do
    assert is_binary(loc["id"])
    assert is_binary(loc["name"])
    assert is_binary(loc["note"])
    assert is_binary(loc["address"])
    # assert is_number(loc["lat"])
    # assert is_number(loc["long"])
    # assert is_number(loc["alt"])
    assert is_map(loc["geom"])
    assert is_binary(loc["uri"])
  end
end
