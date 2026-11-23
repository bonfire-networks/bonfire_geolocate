defmodule Bonfire.Geolocate.MapLiveTest do
  @moduledoc "The map: what its hook sends back as the user moves it or is located."
  # `@moduletag :ui` comes with this case
  use Bonfire.Geolocate.ConnCase, async: true

  import Bonfire.UI.Common.Testing.Helpers, only: [conn: 1]

  setup do
    # maps need a tiles key (not left to the `.env`)
    Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")

    account = fake_account!()
    user = fake_user!(account)
    {:ok, conn: conn(user: user, account: account), user: user}
  end

  test "the map page's map loads the places in view as it moves, and takes the user's location, in the map itself",
       %{conn: conn} do
    Bonfire.Geolocate.Simulate.fake_geolocation!(nil, nil, %{
      name: "Inside Moor",
      lat: 50.5,
      long: -3.5
    })

    Bonfire.Geolocate.Simulate.fake_geolocation!(nil, nil, %{
      name: "Outside Reef",
      lat: 10.0,
      long: 10.0
    })

    {:ok, view, html} = live(conn, "/map")

    # the hook sends where the map is only from a map that loads the places in view
    assert [_] = html |> Floki.parse_document!() |> Floki.find("leaflet-map[live-bounds]")

    # the map's code is loaded by the hook, from its own bundle (not the main one)
    assert [bundle] =
             html
             |> Floki.parse_document!()
             |> Floki.attribute("[phx-hook=MapLeaflet]", "data-map-bundle")

    assert bundle =~ "/assets/geolocate_map.js"

    # the hook sends to the map component (`pushEventTo` its element, which the browser resolves to the component it is in); here, to the component's root element
    map = with_target(view, "[data-id=map]")

    assert render_hook(map, "current_location", %{
             "accuracy" => 35,
             "location" => %{"lat" => 50.43, "lng" => -3.69}
           }) =~ "leaflet-map"

    # the bounds as the hook sends them: Leaflet's polygon rings
    html =
      render_hook(map, "map_bounds", %{
        "bounds" => [
          [
            %{"lat" => 50.0, "lng" => -4.0},
            %{"lat" => 50.0, "lng" => -3.5},
            %{"lat" => 50.0, "lng" => -3.0},
            %{"lat" => 50.5, "lng" => -3.0},
            %{"lat" => 51.0, "lng" => -3.0},
            %{"lat" => 51.0, "lng" => -3.5},
            %{"lat" => 51.0, "lng" => -4.0},
            %{"lat" => 50.5, "lng" => -4.0}
          ]
        ]
      })

    popups =
      html
      |> Floki.parse_document!()
      |> Floki.attribute("leaflet-marker", "popup")

    assert "Inside Moor" in popups
    refute "Outside Reef" in popups
  end

  test "a shape (eg. from GeoJSON, longitude first) is drawn with Leaflet's latitude-first pairs",
       %{
         conn: conn
       } do
    # a square around Totnes, longitude first as GeoJSON and PostGIS have it
    Bonfire.Geolocate.Simulate.fake_geolocation!(nil, nil, %{
      name: "Totnes Square",
      geom: %Geo.Polygon{
        coordinates: [[{-3.7, 50.4}, {-3.6, 50.4}, {-3.6, 50.5}, {-3.7, 50.5}, {-3.7, 50.4}]],
        srid: 4326
      }
    })

    {:ok, _view, html} = live(conn, "/map")

    assert [points | _] =
             html |> Floki.parse_document!() |> Floki.attribute("leaflet-polygon", "points")

    assert [[50.4, -3.7] | _] = Jason.decode!(points)
  end

  test "a guest is asked to sign in to see the map, and gets no map", %{} do
    Bonfire.Geolocate.Simulate.fake_geolocation!(nil, nil, %{
      name: "Hidden Moor",
      lat: 50.5,
      long: -3.5
    })

    {:ok, _view, html} = live(conn(), "/map")
    doc = Floki.parse_document!(html)

    assert [_] = Floki.find(doc, "[data-id=map_signed_out]")
    assert [_ | _] = Floki.find(doc, "[data-id=map_signed_out] a[href='/login']")
    assert [] = Floki.find(doc, "leaflet-map")
    assert [] = Floki.find(doc, "[phx-hook=MapLeaflet]")
    refute html =~ "Hidden Moor"
  end

  describe "without a Mapbox key" do
    setup do
      Process.put([:bonfire, :js_config, :mapbox_api_key], "")

      Process.put(
        [:bonfire_geolocate, Bonfire.Geolocate, :map_styles_url],
        "https://tiles.example.local/styles/"
      )

      :ok
    end

    defp style_url(conn) do
      {:ok, _view, html} = live(conn, "/map")

      html
      |> Floki.parse_document!()
      |> Floki.attribute("leaflet-map", "style-url")
    end

    test "maps use the instance's map style, from its styles' server", %{conn: conn} do
      assert ["https://tiles.example.local/styles/liberty"] = style_url(conn)
    end

    test "a user's map style is used for them", %{conn: conn, user: user} do
      Bonfire.Common.Settings.put([Bonfire.Geolocate, :map_style], "dark",
        current_user: user,
        scope: :user
      )

      assert ["https://tiles.example.local/styles/dark"] = style_url(conn)
    end

    test "a map style given as a full URL (eg. of a self-hosted style) is used as it is", %{
      conn: conn,
      user: user
    } do
      Bonfire.Common.Settings.put(
        [Bonfire.Geolocate, :map_style],
        "https://maps.example.local/protomaps/style.json",
        current_user: user,
        scope: :user
      )

      assert ["https://maps.example.local/protomaps/style.json"] = style_url(conn)
    end

    test "with the Mapbox backend, maps use Mapbox's tiles rather than a style", %{conn: conn} do
      Process.put([:bonfire_geolocate, Bonfire.Geolocate, :maps_backend], :mapbox)
      Process.put([:bonfire, :js_config, :mapbox_api_key], "test-key")

      {:ok, _view, html} = live(conn, "/map")
      doc = Floki.parse_document!(html)

      assert [_] = Floki.find(doc, "leaflet-map")
      assert [] = Floki.attribute(doc, "leaflet-map", "style-url")
    end

    test "with no maps backend, there is no map", %{conn: conn} do
      Process.put([:bonfire_geolocate, Bonfire.Geolocate, :maps_backend], :none)

      {:ok, _view, html} = live(conn, "/map")
      assert html =~ "map_unavailable"
      refute html =~ "<leaflet-map"
    end

    test "with no styles' server either, there is no map", %{conn: conn} do
      Process.put([:bonfire_geolocate, Bonfire.Geolocate, :map_styles_url], "")

      {:ok, _view, html} = live(conn, "/map")
      assert html =~ "map_unavailable"
      refute html =~ "<leaflet-map"
    end
  end
end
