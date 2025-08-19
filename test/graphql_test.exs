if Code.ensure_loaded?(Bonfire.API.GraphQL.Schema) do
  # SPDX-License-Identifier: AGPL-3.0-only
  defmodule Bonfire.Geolocate.GraphQLTest do
    use Bonfire.Geolocate.ConnCase, async: true

    import Bonfire.Common.Simulation
    # import CommonsPub.Utils.Simulate

    import Bonfire.Geolocate.Test.Faking
    import Bonfire.Geolocate.Simulate
    # alias Bonfire.Geolocate.Geolocations

    describe "geolocation" do
      test "fetches a geolocation by ID" do
        user = fake_user!()
        geo = fake_geolocation!(user)

        q = Bonfire.Geolocate.Test.Faking.geolocation_query()
        conn = user_conn(user)

        assert_geolocation(grumble_post_key(q, conn, :spatial_thing, %{id: geo.id}))
      end
    end

    describe "spatialThingPages" do
      @tag :fixme
      test "fetches a paginated list of geolocations" do
        user = fake_user!()
        _geos = some(5, fn -> fake_geolocation!(user) end)

        q = Bonfire.Geolocate.Test.Faking.geolocation_pages_query()
        conn = user_conn(user)

        vars = %{
          limit: 2
        }

        assert geolocations = grumble_post_key(q, conn, :spatial_things_pages, vars)

        assert geolocations["totalCount"] == 5
        assert Enum.count(geolocations["edges"]) == 2
      end
    end

    describe "geolocation.in_scope_of" do
      @tag :fixme
      test "returns the context of the geolocation" do
        user = fake_user!()
        context = fake_geolocation!(user)

        geo = fake_geolocation!(user, context)

        q = Bonfire.Geolocate.Test.Faking.geolocation_query(fields: [in_scope_of: [:__typename]])
        conn = user_conn(user)
        assert resp = grumble_post_key(q, conn, :spatial_thing, %{id: geo.id})
        assert resp["inScopeOf"]["__typename"] == "SpatialThing"
      end

      test "returns nil if there is no context" do
        user = fake_user!()
        geo = fake_geolocation!(user)

        q = Bonfire.Geolocate.Test.Faking.geolocation_query(fields: [in_scope_of: [:__typename]])
        conn = user_conn(user)
        assert resp = grumble_post_key(q, conn, :spatial_thing, %{id: geo.id})
        assert is_nil(resp["inScopeOf"])
      end
    end

    describe "create_geolocation" do
      test "creates a new geolocation" do
        user = fake_user!()

        q = Bonfire.Geolocate.Test.Faking.create_geolocation_mutation()
        conn = user_conn(user)
        vars = %{spatial_thing: geolocation_input()}

        assert_geolocation(grumble_post_key(q, conn, :create_spatial_thing, vars)["spatialThing"])
      end

      test "creates a new geolocation with a context" do
        user = fake_user!()
        context = fake_user!()

        q =
          Bonfire.Geolocate.Test.Faking.create_geolocation_mutation(
            fields: [in_scope_of: [:__typename]]
          )

        conn = user_conn(user)
        vars = %{spatial_thing: geolocation_input(), in_scope_of: context.id}

        assert_geolocation(grumble_post_key(q, conn, :create_spatial_thing, vars)["spatialThing"])
      end

      test "creates a new geolocation with a mappable address" do
        user = fake_user!()

        q = Bonfire.Geolocate.Test.Faking.create_geolocation_mutation()
        conn = user_conn(user)

        vars = %{
          spatial_thing: geolocation_input(%{"lat" => nil, "long" => nil})
        }

        vars = put_in(vars, [:spatial_thing, "mappableAddress"], mappable_address())

        assert geo =
                 grumble_post_key(q, conn, :create_spatial_thing, vars)[
                   "spatialThing"
                 ]

        assert_geolocation(geo)
        assert geo["lat"]
        assert geo["long"]
      end
    end

    describe "update_geolocation" do
      test "updates an existing geolocation" do
        user = fake_user!()
        geo = fake_geolocation!(user)

        q = Bonfire.Geolocate.Test.Faking.update_geolocation_mutation()
        conn = user_conn(user)
        vars = %{spatial_thing: Map.put(geolocation_input(), "id", geo.id)}

        assert_geolocation(grumble_post_key(q, conn, :update_spatial_thing, vars)["spatialThing"])
      end

      test "updates an existing geolocation with only a name" do
        user = fake_user!()
        geo = fake_geolocation!(user)

        q = Bonfire.Geolocate.Test.Faking.update_geolocation_mutation()
        conn = user_conn(user)

        vars = %{
          spatial_thing: %{
            "id" => geo.id,
            "name" => geolocation_input()["name"]
          }
        }

        assert updated =
                 grumble_post_key(q, conn, :update_spatial_thing, vars)[
                   "spatialThing"
                 ]

        assert_geolocation(updated)
        assert updated["name"] == vars[:spatial_thing]["name"]
      end

      # FIXME (Geocoder times out)
      @tag :skip
      test "updates an existing geolocation with a mappable address" do
        user = fake_user!()
        geo = fake_geolocation!(user)

        q = Bonfire.Geolocate.Test.Faking.update_geolocation_mutation()
        conn = user_conn(user)

        vars = %{
          spatial_thing:
            Map.merge(geolocation_input(), %{
              "id" => geo.id,
              "mappableAddress" => mappable_address()
            })
        }

        assert updated =
                 grumble_post_key(q, conn, :update_spatial_thing, vars)[
                   "spatialThing"
                 ]

        assert_geolocation(updated)
        assert geo.lat != updated["lat"]
        assert geo.long != updated["long"]
      end
    end

    describe "delete_geolocation" do
      test "deletes an existing geolocation" do
        user = fake_user!()
        geo = fake_geolocation!(user)

        q = Bonfire.Geolocate.Test.Faking.delete_geolocation_mutation()
        conn = user_conn(user)
        assert grumble_post_key(q, conn, :delete_spatial_thing, %{id: geo.id})
      end

      test "fails to delete a location of another user unless an admin" do
        q = Bonfire.Geolocate.Test.Faking.delete_geolocation_mutation()
        # first user is admin
        admin = fake_user!()
        user = fake_user!()
        guest = fake_user!()

        geo = fake_geolocation!(user)
        conn = user_conn(guest)

        assert [%{"status" => 403}] = grumble_post_errors(q, conn, %{id: geo.id})

        conn = user_conn(user)
        assert grumble_post_key(q, conn, :delete_spatial_thing, %{id: geo.id})

        # regenerate new to re-delete
        geo = fake_geolocation!(user)
        conn = user_conn(admin)
        assert grumble_post_key(q, conn, :delete_spatial_thing, %{id: geo.id})
      end
    end
  end
end
