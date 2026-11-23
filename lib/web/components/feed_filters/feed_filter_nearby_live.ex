defmodule Bonfire.Geolocate.FeedFilterNearbyLive do
  @moduledoc """
  The feed filters editor's "Nearby" row: things within a radius of the viewer, where they have a place (eg. events). A stateless control the editor renders (see `Bonfire.UI.Common.FeedFilterControlModule`); its events are handled by `Bonfire.Geolocate.LiveHandler`, which is given the editor's own socket.

  The radius is shown in the viewer's units (the `:measurement_units` setting), while the filter always holds kilometres.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Geolocate.ViewerLocation

  declare_feed_filter_control(:nearby, filters: [nearby: nil], after: :happening)

  @doc "The editor's DOM id, used to build this row's ids."
  prop id, :string, required: true
  @doc "The editor's pending filters."
  prop feed_filters, :any, default: nil
  @doc "Where this row's events go: the editor."
  prop target, :any, default: nil
  @doc "What the editor keeps for controls between events, by control name."
  prop control_state, :map, default: %{}

  @radii [5, 10, 25, 50, 100]
  @km_per_mile 1.609344

  @doc "The radius choices, in the viewer's units."
  def radii, do: @radii

  @doc "`:imperial` or `:metric`, from the viewer's setting."
  def units(context) do
    case Settings.get(:measurement_units, :metric, context) do
      units when units in [:imperial, "imperial"] -> :imperial
      _ -> :metric
    end
  end

  @doc "A radius chosen in the viewer's units, as the kilometres the filter holds."
  def to_km(radius, :imperial), do: Float.round(radius * @km_per_mile, 2)
  def to_km(radius, _metric), do: radius

  @doc "Kilometres, in the viewer's units: the nearest of the choices when imperial."
  def from_km(km, :imperial) when is_number(km),
    do: Enum.min_by(@radii, &abs(&1 - km / @km_per_mile))

  def from_km(km, _metric), do: km

  @doc "The summary in the row's header."
  def summary(filters, units) do
    case e(filters, :nearby, nil) do
      %{km: km} when is_number(km) ->
        case units do
          :imperial -> l("Within %{mi} mi", mi: from_km(km, units))
          _ -> l("Within %{km} km", km: from_km(km, units))
        end

      _ ->
        l("Anywhere")
    end
  end

  @doc "Whether things with no place (eg. online events) are included: unless the filter says not."
  def include_no_place?(filters), do: e(filters, :nearby, :include_no_place, true) != false

  @doc "Where the viewer is, from their setting only (nothing is geocoded here), or nil."
  def viewer_location(context) do
    ViewerLocation.resolve(context, geocode: fn _ -> {:error, nil} end)
  end

  @doc "The name to show in the place field: what was typed for this search while that is still the point searched, else the name saved with the viewer's location."
  def place_name(filters, control_state, viewer) do
    point = nearby_point(e(filters, :nearby, nil))
    place = e(control_state, :nearby, :place, nil)

    cond do
      place && point && same_point?(place, point) -> place.name
      viewer && (is_nil(point) || same_point?(viewer, point)) -> viewer[:name]
      true -> nil
    end
  end

  defp nearby_point(%{lat: lat, long: long}), do: %{lat: lat, long: long}
  defp nearby_point(_), do: nil

  defp same_point?(%{lat: lat1, long: long1}, %{lat: lat2, long: long2}),
    do: abs(lat1 - lat2) < 0.0005 and abs(long1 - long2) < 0.0005

  defp same_point?(_, _), do: false
end
