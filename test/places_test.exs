defmodule Bonfire.Geolocate.PlacesTest do
  @moduledoc "Listing places, and the places within an area (what a map shows as it moves)."
  # `@moduletag :backend` comes with this case
  use Bonfire.Geolocate.DataCase, async: true

  import Bonfire.Geolocate.Simulate
  alias Bonfire.Geolocate.Geolocations
  alias Bonfire.Geolocate.Places

  # the maps backend chosen by the env (`MAPS_BACKEND`)
  doctest Bonfire.Geolocate.RuntimeConfig, import: true

  # an area, as MapLive builds it from the map's bounds: a closed ring of points, longitude first (as stored)
  @area %Geo.Polygon{
    coordinates: [
      [{-4.0, 50.0}, {-3.0, 50.0}, {-3.0, 51.0}, {-4.0, 51.0}, {-4.0, 50.0}]
    ],
    srid: 4326
  }

  setup do
    {:ok,
     inside: fake_geolocation!(nil, nil, %{name: "Inside Moor", lat: 50.5, long: -3.5}),
     outside: fake_geolocation!(nil, nil, %{name: "Outside Reef", lat: 10.0, long: 10.0})}
  end

  test "a place made from a latitude and longitude stores its point longitude first (as `Geo.Point` and PostGIS do), and reads back the same latitude and longitude" do
    place = fake_geolocation!(nil, nil, %{name: "Totnes", lat: 50.43, long: -3.68})

    assert %{geom: %Geo.Point{coordinates: {-3.68, 50.43}}} =
             Bonfire.Common.Repo.get!(Bonfire.Geolocate.Geolocation, place.id)

    assert %{lat: 50.43, long: -3.68} =
             Bonfire.Common.Repo.get!(Bonfire.Geolocate.Geolocation, place.id)
             |> Geolocations.populate_coordinates()
  end

  test "places near a point, by their true distance (east-west too)" do
    # about 2 km and 50 km east of Totnes (a degree of longitude is about 71 km at 50°N)
    near_east = fake_geolocation!(nil, nil, %{name: "Near East", lat: 50.43, long: -3.68 + 0.028})
    far_east = fake_geolocation!(nil, nil, %{name: "Far East", lat: 50.43, long: -3.68 + 0.7})
    totnes = %Geo.Point{coordinates: {-3.68, 50.43}, srid: 4326}

    assert {:ok, %{edges: edges}} =
             Geolocations.many_paginated([{:near_point, totnes, :distance_meters, 10_000}])

    ids = Enum.map(edges, & &1.id)
    assert near_east.id in ids
    refute far_east.id in ids
  end

  test "places are listed a page at a time, with their coordinates", %{inside: inside} do
    assert {:ok, %{edges: edges}} = Geolocations.many_paginated(location_within: @area)
    assert [%{id: id, lat: 50.5, long: -3.5}] = edges
    assert id == inside.id
  end

  test "the places within an area are only those in it", %{inside: inside, outside: outside} do
    assert %{edges: edges} = Places.fetch_place_things([location_within: @area], [])
    ids = Enum.map(edges, & &1.id)

    assert inside.id in ids
    refute outside.id in ids
  end
end
