# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Geolocate.GeolocationsTest do
  use Bonfire.Geolocate.ConnCase, async: true

  import Bonfire.Common.Simulation
  # import CommonsPub.Utils.Simulate

  import Bonfire.Geolocate.Test.Faking
  import Bonfire.Geolocate.Simulate
  alias Bonfire.Geolocate.Geolocations

  describe "one" do
    test "fetches an existing geolocation" do
      user = fake_user!()
      context = fake_user!()
      geo = fake_geolocation!(user, context)

      assert {:ok, fetched} = Geolocations.one(id: geo.id)
      assert_geolocation(fetched)
      assert {:ok, fetched} = Geolocations.one(user: user)
      assert_geolocation(fetched)
      # assert {:ok, fetched} = Geolocations.one(username: geo.character.preferred_username)
      # assert_geolocation(fetched)
      assert {:ok, fetched} = Geolocations.one(context_id: context.id)
      assert_geolocation(fetched)
    end

    test "default ignores items that are deleted" do
      user = fake_user!()
      geo = fake_geolocation!(user)

      assert {:ok, geo} = Geolocations.soft_delete(geo, user)

      assert {:error, :not_found} =
               Geolocations.one([:default, id: geo.id])
    end
  end

  describe "create" do
    test "creates a new geolocation" do
      user = fake_user!()

      assert {:ok, geo} = Geolocations.create(user, geolocation())
      assert_geolocation(geo)
    end

    test "creates a new geolocation with a context" do
      user = fake_user!()
      context = fake_user!()

      assert {:ok, geo} = Geolocations.create(user, context, geolocation())
      assert_geolocation(geo)
      assert geo.context_id == context.id
    end

    test "creates a geolocation with a mappable address" do
      user = fake_user!()

      attrs = Map.put(geolocation(), :mappable_address, mappable_address())
      assert {:ok, geo} = Geolocations.create(user, attrs)
      assert_geolocation(geo)
      assert geo.lat
      assert geo.long
    end
  end

  describe "update" do
    test "update an exisitng geolocation" do
      user = fake_user!()
      geo = fake_geolocation!(user)

      assert {:ok, updated} = Geolocations.update(user, geo, geolocation())
      assert_geolocation(updated)
      assert updated.id == geo.id
      assert updated != geo
    end

    test "update an existing geolocation with a mappable address" do
      user = fake_user!()
      geo = fake_geolocation!(user)

      attrs = Map.put(geolocation(), :mappable_address, mappable_address())
      assert {:ok, geo} = Geolocations.update(user, geo, attrs)
      assert geo.lat
      assert geo.long
      assert geo.mappable_address == attrs[:mappable_address]
    end

    test "update an existing location with only a name" do
      user = fake_user!()
      geo = fake_geolocation!(user)

      new_attrs = %{name: geolocation().name}
      assert {:ok, updated} = Geolocations.update(user, geo, new_attrs)
      assert updated.name == new_attrs.name
    end
  end

  describe "soft_delete" do
    test "deletes an existing geolocation" do
      user = fake_user!()
      geo = fake_geolocation!(user)
      refute geo.deleted_at
      assert {:ok, geo} = Geolocations.soft_delete(geo, user)
      assert geo.deleted_at
    end
  end
end
