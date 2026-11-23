defmodule Bonfire.Geolocate.ViewerLocation do
  @moduledoc """
  Where the viewer is, for things like the "nearby" feed filter.

  In order: the user's location setting (`[Bonfire.Geolocate, :location]`, per user, cascading from the instance), then the profile's own `location` text. The setting holds coordinates as `"lat,long"` rounded to about 100 m (3 decimals), or, when set by hand for the weather widget, a place name to geocode. The profile's location is only read, never written; a location detected by the browser is saved to the setting only.

  Geocoding a place name calls an outside service (`Bonfire.Geolocate.Geocode`), so it only happens when the setting has no coordinates, and callers should keep the result rather than call this on each render or query.
  """
  use Bonfire.Common.Utils
  use Bonfire.Common.Settings

  @setting_keys [Bonfire.Geolocate, :location]
  @name_setting_keys [Bonfire.Geolocate, :location_name]

  @doc """
  Reads coordinates from `"lat,long"`, or returns nil for text and out-of-range numbers.

      iex> Bonfire.Geolocate.ViewerLocation.parse("50.432,-3.684")
      %{lat: 50.432, long: -3.684}
      iex> Bonfire.Geolocate.ViewerLocation.parse("Totnes")
      nil
  """
  def parse(text) when is_binary(text) do
    with [lat, long] <- String.split(text, ",", parts: 2),
         {lat, ""} when lat >= -90 and lat <= 90 <- Float.parse(String.trim(lat)),
         {long, ""} when long >= -180 and long <= 180 <- Float.parse(String.trim(long)) do
      %{lat: lat, long: long}
    else
      _ -> nil
    end
  end

  def parse(_), do: nil

  @doc "Coordinates as the string the setting holds, rounded to 3 decimals (about 110 m)."
  def format(lat, long), do: "#{Float.round(lat / 1, 3)},#{Float.round(long / 1, 3)}"

  @doc """
  The viewer's location as `%{lat, long, source: :setting | :profile}`, or nil when there is none.

  Options: `:geocode`, a function from text to `{:ok, %{lat: _, lon: _}}` or an error (default `Bonfire.Geolocate.Geocode.coordinates/1`).
  """
  def resolve(context, opts \\ []) do
    geocode = opts[:geocode] || (&Bonfire.Geolocate.Geocode.coordinates/1)
    setting = Settings.get(@setting_keys, nil, context)

    from_setting(setting, geocode, context) || from_profile(context, geocode)
  end

  defp from_setting(text, geocode, context) when is_binary(text) and text != "" do
    case parse(text) do
      %{lat: lat, long: long} ->
        %{lat: lat, long: long, source: :setting, name: saved_name(context)}

      nil ->
        # a place name set by hand is its own name
        case geocoded(text, geocode) do
          %{lat: lat, long: long} -> %{lat: lat, long: long, source: :setting, name: text}
          _ -> nil
        end
    end
  end

  defp from_setting(_, _, _), do: nil

  # the name kept beside the coordinates, in its own setting so that the location setting stays a plain "lat,long" that the weather widget can read
  defp saved_name(context) do
    case Settings.get(@name_setting_keys, nil, context) do
      name when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  defp from_profile(context, geocode) do
    case e(current_user(context), :profile, :location, nil) do
      text when is_binary(text) and text != "" ->
        case geocoded(text, geocode) do
          %{lat: lat, long: long} -> %{lat: lat, long: long, source: :profile, name: text}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp geocoded(text, geocode) do
    case geocode.(text) do
      {:ok, %{lat: lat, lon: long}} when is_number(lat) and is_number(long) ->
        %{lat: lat, long: long}

      _ ->
        nil
    end
  end

  @doc """
  Saves a location to the user's location setting (rounded), and returns it. The place's name, if known (eg. a city, or the profile's text), is kept in a setting of its own beside it, so showing it costs nothing later; a save without a name clears the old one, which would belong to another place.
  """
  def save(context, lat, long, name \\ nil) when is_number(lat) and is_number(long) do
    text = format(lat, long)
    user = current_user(context)

    # both in one write: a second `put` would start from the user's settings as they were loaded, and drop the first
    with {:ok, _} <-
           Settings.set(
             %{Bonfire.Geolocate => %{location: text, location_name: name || ""}},
             current_user: user,
             scope: :user
           ) do
      {:ok, parse(text)}
    end
  end
end
