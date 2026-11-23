defmodule Bonfire.Geolocate.KnownCoordinatesExplainTest do
  @moduledoc "The lookup of a place already saved with the same address uses its expression index on a table big enough for the planner to prefer it. Asserted on the plan, as a small table is scanned whatever the query's shape."
  use Bonfire.Geolocate.DataCase, async: false

  # slow (inserts thousands of rows), so excluded by default: run it with `just test extensions/bonfire_geolocate/test/known_coordinates_explain_test.exs --include explain`
  @moduletag :explain

  import Ecto.Query
  alias Bonfire.Common.Repo
  alias Bonfire.Geolocate.Geolocation

  @index "bonfire_geolocate_geolocation_mappable_address_index"
  @places 4000

  defp insert_places! do
    geolocation_table_id = Needle.Util.table_id(Geolocation)

    places =
      for i <- 1..@places do
        %{
          id: Needle.UID.generate(),
          updated_at: DateTime.utc_now(),
          mappable_address: "  #{i} High Street, Totnes  ",
          geom: %Geo.Point{coordinates: {-3.68, 50.43}, srid: 4326}
        }
      end

    Repo.insert_all(
      Needle.Pointer,
      Enum.map(places, &%{id: &1.id, table_id: geolocation_table_id})
    )

    Repo.insert_all(Geolocation, places)
    Repo.query!("ANALYZE bonfire_geolocate_geolocation")
  end

  # the same query as `known_coordinates/1`
  defp lookup_query(address) do
    normalised = address |> String.trim() |> String.downcase()

    from(g in Geolocation,
      where: fragment("lower(trim(?))", g.mappable_address) == ^normalised and not is_nil(g.geom),
      select: g.geom,
      limit: 1
    )
  end

  test "the lookup by address uses the expression index" do
    insert_places!()

    {sql, params} = Repo.to_sql(:all, lookup_query("1234 High Street, TOTNES"))
    %{rows: rows} = Repo.query!("EXPLAIN " <> sql, params)
    plan = rows |> List.flatten() |> Enum.join("\n")

    assert plan =~ @index, plan
  end
end
