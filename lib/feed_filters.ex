defmodule Bonfire.Geolocate.FeedFilters do
  @moduledoc """
  Narrows a feed to things whose place (the `primary_geolocation` mixin, eg. of an event) is within a radius of a point: `nearby: %{lat: .., long: .., km: .., include_no_place: true}`.

  Things with no place are included unless `include_no_place` is false, as an online or global event has none (no `VirtualLocation` is stored yet).

  `within_bounds: %{south: .., west: .., north: .., east: ..}` (degrees) narrows it to things whose place is inside a box, as a map reports the area in view (west and east may lie past 180, and a box over the antimeridian takes both sides of it); things with no place are left out. `within_bounds: %{has_place: true}` takes only the things that have a place, wherever.

  Lives here rather than in the feed loader because a geolocation is this extension's. The key is declared as a field on `Bonfire.Social.FeedFilters` from this extension's config, and this module applies it; `Bonfire.Common.FeedFilterModule` explains why the two halves are declared in different places.
  """
  use Bonfire.Common.Utils, only: []
  import Ecto.Query

  @behaviour Bonfire.Common.FeedFilterModule

  @impl true
  def feed_filter_module, do: __MODULE__

  @impl true
  def maybe_filter(query, filter, opts \\ [])

  def maybe_filter(query, {:nearby, %{} = nearby}, _opts) do
    with lat when is_number(lat) <- number(nearby, :lat),
         long when is_number(long) <- number(nearby, :long),
         km when is_number(km) and km > 0 <- number(nearby, :km) do
      meters = km * 1000.0
      include_no_place? = value(nearby, :include_no_place) not in [false, "false"]

      where(query, ^nearby_where(lat, long, meters, include_no_place?))
    else
      _ -> query
    end
  end

  def maybe_filter(query, {:within_bounds, %{} = bounds}, _opts) do
    case boxes(bounds) do
      [] ->
        # no box (or no usable one): only the things that have a place at all
        if value(bounds, :has_place) in [true, "true"],
          do: where(query, ^has_place_where()),
          else: query

      boxes ->
        where(query, ^bounds_where(boxes))
    end
  end

  def maybe_filter(query, _filter, _opts), do: query

  # the boxes `{south, west, north, east}` a bounding box is, in degrees: the latitudes held to the globe, the longitudes wrapped round it, so a box past the antimeridian (as a map panned round the world reports it, eg. 170 to 190) is two boxes, and one a whole turn wide (or more) is every longitude. No boxes when a side is missing or not a number
  defp boxes(bounds) do
    with south when is_number(south) <- number(bounds, :south),
         west when is_number(west) <- number(bounds, :west),
         north when is_number(north) <- number(bounds, :north),
         east when is_number(east) <- number(bounds, :east),
         true <- south <= north and west <= east do
      south = max(south, -90.0) * 1.0
      north = min(north, 90.0) * 1.0

      cond do
        east - west >= 360 ->
          [{south, -180.0, north, 180.0}]

        true ->
          west = wrap_longitude(west)
          east = wrap_longitude(east)

          if west <= east,
            do: [{south, west, north, east}],
            else: [{south, west, north, 180.0}, {south, -180.0, north, east}]
      end
    else
      _ -> []
    end
  end

  # a longitude as one of -180 up to 180
  defp wrap_longitude(long) do
    turns = (long + 180) / 360
    (turns - Float.floor(turns)) * 360 - 180
  end

  # an `EXISTS` too (as for `nearby`): in any of the boxes, which the geography index serves
  defp bounds_where(boxes) do
    within =
      Enum.reduce(boxes, dynamic(false), fn box, any ->
        dynamic(^any or ^Bonfire.Geolocate.Queries.within_box(:place, box))
      end)

    dynamic(
      exists(
        from(pg in "bonfire_geolocate_primary_geolocation",
          join: g in Bonfire.Geolocate.Geolocation,
          as: :place,
          on: g.id == pg.geolocation_id,
          where: pg.id == parent_as(:object).id,
          where: ^within,
          select: 1
        )
      )
    )
  end

  defp has_place_where do
    dynamic(
      exists(
        from(pg in "bonfire_geolocate_primary_geolocation",
          join: g in Bonfire.Geolocate.Geolocation,
          on: g.id == pg.geolocation_id,
          where: pg.id == parent_as(:object).id and not is_nil(g.geom),
          select: 1
        )
      )
    )
  end

  # the distance query is the context's (`Bonfire.Geolocate.Queries.within_meters/3`, as `near_point` uses); points are longitude first
  # correlated `EXISTS` subqueries rather than joins: an `OR` over a joined column stops Postgres using the `geom::geography` index, while each `EXISTS` can
  defp nearby_where(lat, long, meters, include_no_place?) do
    point = %Geo.Point{coordinates: {long, lat}, srid: 4326}

    within =
      dynamic(
        exists(
          from(pg in "bonfire_geolocate_primary_geolocation",
            join: g in Bonfire.Geolocate.Geolocation,
            as: :place,
            on: g.id == pg.geolocation_id,
            where: pg.id == parent_as(:object).id,
            where: ^Bonfire.Geolocate.Queries.within_meters(:place, point, meters),
            select: 1
          )
        )
      )

    if include_no_place? do
      with_geom =
        dynamic(
          exists(
            from(pg in "bonfire_geolocate_primary_geolocation",
              join: g in Bonfire.Geolocate.Geolocation,
              on: g.id == pg.geolocation_id,
              where: pg.id == parent_as(:object).id and not is_nil(g.geom),
              select: 1
            )
          )
        )

      dynamic(not (^with_geom) or ^within)
    else
      within
    end
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))

  defp number(map, key) do
    case value(map, key) do
      n when is_number(n) ->
        n

      s when is_binary(s) ->
        case Float.parse(s) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end
end
