defmodule Bonfire.Geolocate.FeedFilterNearbyExplainTest do
  @moduledoc "The nearby feed filter's plan on a table big enough for the planner to prefer the spatial index: in the default mode too (things with no place included), not only the strict one. Asserted on the plan, as a small table is scanned whatever the query's shape."
  use Bonfire.Geolocate.DataCase, async: false

  # slow (inserts thousands of rows), so excluded by default: run it with `just test extensions/bonfire_geolocate/test/feed_filter_nearby_explain_test.exs --include explain`
  @moduletag :explain

  import Ecto.Query
  import Geo.PostGIS, only: [st_dwithin_in_meters: 3]
  alias Bonfire.Common.Repo
  alias Bonfire.Geolocate.Geolocation
  alias Bonfire.Geolocate.PrimaryGeolocation
  alias Bonfire.Social.FeedLoader

  @index "bonfire_geolocate_geolocation_geom_geography_index"
  @places 4000

  # Totnes
  @here %{lat: 50.4319, long: -3.6837}

  defp insert_places! do
    :rand.seed(:exsss, {1, 2, 3})
    geolocation_table_id = Needle.Util.table_id(Geolocation)
    post_table_id = Needle.Util.table_id(Bonfire.Data.Social.Post)

    places =
      for _ <- 1..@places do
        %{
          id: Needle.UID.generate(),
          updated_at: DateTime.utc_now(),
          # spread over the world, so a 25 km radius is selective
          geom: %Geo.Point{
            coordinates: {:rand.uniform() * 360 - 180, :rand.uniform() * 160 - 80},
            srid: 4326
          }
        }
      end

    objects = for _ <- places, do: Needle.UID.generate()

    Repo.insert_all(
      Needle.Pointer,
      Enum.map(places, &%{id: &1.id, table_id: geolocation_table_id}) ++
        Enum.map(objects, &%{id: &1, table_id: post_table_id})
    )

    Repo.insert_all(Geolocation, places)

    Repo.insert_all(
      PrimaryGeolocation,
      places |> Enum.zip(objects) |> Enum.map(fn {p, o} -> %{id: o, geolocation_id: p.id} end)
    )

    # an activity per post, as in production, so the feed's outer side has real rows
    subject_id = Bonfire.Me.Fake.fake_user!().id
    verb_id = Bonfire.Boundaries.Verbs.get_id!(:create)

    Repo.insert_all(
      Bonfire.Data.Social.Activity,
      Enum.map(objects, &%{id: &1, subject_id: subject_id, verb_id: verb_id, object_id: &1})
    )

    # stats of every table the plan touches, so they don't depend on leftovers or autovacuum
    for table <- [
          "bonfire_geolocate_geolocation",
          "bonfire_geolocate_primary_geolocation",
          "bonfire_data_social_activity",
          "pointers_pointer",
          "bonfire_data_access_control_controlled",
          "bonfire_data_access_control_grant",
          "bonfire_data_access_control_encircle"
        ] do
      Repo.query!("ANALYZE " <> table)
    end
  end

  defp explain(query) do
    {sql, params} = Repo.to_sql(:all, query)
    %{rows: rows} = Repo.query!("EXPLAIN " <> sql, params)
    rows |> List.flatten() |> Enum.join("\n")
  end

  defp feed_query(filters) do
    FeedLoader.query(filters, current_user: Bonfire.Me.Fake.fake_user!())
  end

  # the shape the filter had before: left joins, then `no geom OR within`, which the planner cannot serve from the index
  defp joined_or_query(nearby) do
    point = %Geo.Point{coordinates: {nearby.long, nearby.lat}, srid: 4326}
    meters = nearby.km * 1000.0

    feed_query(%{})
    |> join(:left, [object: o], pg in "bonfire_geolocate_primary_geolocation",
      as: :old_primary,
      on: pg.id == o.id
    )
    |> join(:left, [old_primary: pg], g in Geolocation,
      as: :old_geolocation,
      on: g.id == pg.geolocation_id
    )
    |> where(
      [old_geolocation: g],
      is_nil(g.geom) or st_dwithin_in_meters(g.geom, ^point, ^meters)
    )
  end

  test "the default and the strict nearby both use the geography index" do
    insert_places!()
    nearby = Map.merge(@here, %{km: 25})

    old = explain(joined_or_query(nearby))
    default = explain(feed_query(%{nearby: nearby}))
    strict = explain(feed_query(%{nearby: Map.put(nearby, :include_no_place, false)}))

    refute old =~ @index, "expected the old shape to miss the index:\n#{old}"
    assert default =~ @index, "default mode:\n#{default}\n\nold shape:\n#{old}"
    assert strict =~ @index, "strict mode:\n#{strict}"
  end

  test "the bounding box filter uses the geography index too, for a small box and one across the antimeridian" do
    insert_places!()

    small =
      explain(feed_query(%{within_bounds: %{south: 50.0, west: -4.0, north: 51.0, east: -3.0}}))

    across =
      explain(feed_query(%{within_bounds: %{south: -30.0, west: 170.0, north: 0.0, east: 190.0}}))

    assert small =~ @index, "small box:\n#{small}"
    assert across =~ @index, "across the antimeridian:\n#{across}"
  end
end
