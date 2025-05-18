defmodule Bonfire.Geolocate.GeoUtilsTest do
  use Bonfire.Common.Utils
  use ExUnit.Case, async: true

  alias Bonfire.Geolocate.Geolocations

  @postgis_srid 4326

  describe "extract_coordinates/1" do
    test "extracts coordinates from a Geo.Point" do
      point = %Geo.Point{coordinates: {51.5, -0.1}, srid: @postgis_srid}
      assert Geolocations.extract_coordinates(point) == {51.5, -0.1}
    end

    test "extracts coordinates from a Geo.PointZ" do
      point = %Geo.PointZ{coordinates: {51.5, -0.1, 10.0}, srid: @postgis_srid}
      assert Geolocations.extract_coordinates(point) == {51.5, -0.1}
    end

    test "extracts coordinates from a LineString" do
      linestring = %Geo.LineString{
        coordinates: [{51.5, -0.1}, {51.6, -0.2}, {51.7, -0.3}],
        srid: @postgis_srid
      }

      # Should extract from first point
      assert Geolocations.extract_coordinates(linestring) == {51.5, -0.1}
    end

    test "extracts coordinates from a Polygon" do
      polygon = %Geo.Polygon{
        coordinates: [
          [{51.5, -0.1}, {51.6, -0.2}, {51.7, -0.3}, {51.5, -0.1}]
        ],
        srid: @postgis_srid
      }

      # Should extract from first point of first ring
      assert Geolocations.extract_coordinates(polygon) == {51.5, -0.1}
    end

    test "extracts coordinates from a MultiPoint" do
      multipoint = %Geo.MultiPoint{
        coordinates: [{51.5, -0.1}, {51.6, -0.2}, {51.7, -0.3}],
        srid: @postgis_srid
      }

      # Should extract from first point
      assert Geolocations.extract_coordinates(multipoint) == {51.5, -0.1}
    end

    test "extracts coordinates from a MultiLineString" do
      multilinestring = %Geo.MultiLineString{
        coordinates: [
          [{51.5, -0.1}, {51.6, -0.2}],
          [{52.5, -1.1}, {52.6, -1.2}]
        ],
        srid: @postgis_srid
      }

      # Should extract from first point of first line
      assert Geolocations.extract_coordinates(multilinestring) == {51.5, -0.1}
    end

    test "extracts coordinates from a MultiPolygon" do
      multipolygon = %Geo.MultiPolygon{
        coordinates: [
          [
            [{51.5, -0.1}, {51.6, -0.2}, {51.7, -0.3}, {51.5, -0.1}]
          ],
          [
            [{52.5, -1.1}, {52.6, -1.2}, {52.7, -1.3}, {52.5, -1.1}]
          ]
        ],
        srid: @postgis_srid
      }

      # Should extract from first point of first polygon's first ring
      assert Geolocations.extract_coordinates(multipolygon) == {51.5, -0.1}
    end

    test "extracts coordinates from a GeometryCollection with Point" do
      geometrycollection = %Geo.GeometryCollection{
        geometries: [
          %Geo.Point{coordinates: {51.5, -0.1}, srid: @postgis_srid},
          %Geo.LineString{
            coordinates: [{52.5, -1.1}, {52.6, -1.2}],
            srid: @postgis_srid
          }
        ],
        srid: @postgis_srid
      }

      # Should extract from first geometry (Point)
      assert Geolocations.extract_coordinates(geometrycollection) == {51.5, -0.1}
    end

    test "handles empty GeometryCollection" do
      geometrycollection = %Geo.GeometryCollection{geometries: [], srid: @postgis_srid}
      assert Geolocations.extract_coordinates(geometrycollection) == {0, 0}
    end

    test "handles nil input" do
      assert Geolocations.extract_coordinates(nil) == {0, 0}
    end

    test "handles list coordinates format" do
      point = %{coordinates: [51.5, -0.1]}
      assert Geolocations.extract_coordinates(point) == {51.5, -0.1}
    end

    test "handles tuple coordinates format" do
      point = %{coordinates: {51.5, -0.1}}
      assert Geolocations.extract_coordinates(point) == {51.5, -0.1}
    end

    test "handles invalid input" do
      assert Geolocations.extract_coordinates(%{coordinates: "invalid"}) == {0, 0}
    end
  end

  describe "extract_geojson_geometry/1" do
    test "converts GeoJSON Point to Geo.Point" do
      geojson = %{
        "type" => "Point",
        # GeoJSON is [longitude, latitude]
        "coordinates" => [-0.1, 51.5]
      }

      result = Geolocations.extract_geojson_geometry(geojson)

      assert %Geo.Point{} = result
      # Elixir Geo uses {lat, lon}
      assert result.coordinates == {51.5, -0.1}
      assert result.srid == @postgis_srid
    end

    test "converts GeoJSON LineString to Geo.LineString" do
      geojson = %{
        "type" => "LineString",
        "coordinates" => [[-0.1, 51.5], [-0.2, 51.6]]
      }

      result = Geolocations.extract_geojson_geometry(geojson)

      assert %Geo.LineString{} = result
      assert result.coordinates == [{51.5, -0.1}, {51.6, -0.2}]
      assert result.srid == @postgis_srid
    end

    test "converts GeoJSON Polygon to Geo.Polygon" do
      geojson = %{
        "type" => "Polygon",
        "coordinates" => [
          [[-0.1, 51.5], [-0.2, 51.6], [-0.3, 51.7], [-0.1, 51.5]]
        ]
      }

      result = Geolocations.extract_geojson_geometry(geojson)

      assert %Geo.Polygon{} = result

      assert result.coordinates == [
               [{51.5, -0.1}, {51.6, -0.2}, {51.7, -0.3}, {51.5, -0.1}]
             ]

      assert result.srid == @postgis_srid
    end

    test "converts GeoJSON MultiPolygon to Geo.MultiPolygon" do
      geojson = %{
        "type" => "MultiPolygon",
        "coordinates" => [
          [
            [[-0.1, 51.5], [-0.2, 51.6], [-0.3, 51.7], [-0.1, 51.5]]
          ],
          [
            [[-1.1, 52.5], [-1.2, 52.6], [-1.3, 52.7], [-1.1, 52.5]]
          ]
        ]
      }

      result = Geolocations.extract_geojson_geometry(geojson)

      assert %Geo.MultiPolygon{} = result

      assert result.coordinates == [
               [
                 [{51.5, -0.1}, {51.6, -0.2}, {51.7, -0.3}, {51.5, -0.1}]
               ],
               [
                 [{52.5, -1.1}, {52.6, -1.2}, {52.7, -1.3}, {52.5, -1.1}]
               ]
             ]

      assert result.srid == @postgis_srid
    end

    test "handles unsupported GeoJSON type" do
      geojson = %{
        "type" => "UnsupportedType",
        "coordinates" => []
      }

      assert is_nil(Geolocations.extract_geojson_geometry(geojson))
    end

    test "handles nil input" do
      assert is_nil(Geolocations.extract_geojson_geometry(nil))
    end
  end
end
