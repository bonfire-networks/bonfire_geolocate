defmodule Bonfire.Geolocate.WidgetForecastLive do
  @moduledoc """
  A professional weather widget displaying current conditions with astronomical data.

  Shows:
  - Current temperature with feels-like and high/low
  - Weather description and icon
  - Wind speed and direction
  - Humidity and UV index
  - Sunrise/sunset times
  - Moon phase
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop location, :string, default: nil

  declare_settings(:select, l("Measurement Units"),
    keys: [:measurement_units],
    options: [
      metric: l("Metric (meters, celsius, etc)"),
      imperial: l("Imperial (miles, fahrenheit, etc)")
    ],
    default_value: :metric,
    description: l("Select units to use for distance, temperature, etc."),
    scope: :user
  )

  @doc """
  Converts wind bearing (degrees) to compass direction.
  """
  def wind_direction(nil), do: nil

  def wind_direction(bearing) when is_number(bearing) do
    directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    index = round(bearing / 45) |> rem(8)
    Enum.at(directions, index)
  end

  def wind_direction(_), do: nil

  @doc """
  Converts UV index number to human-readable category.
  """
  def uv_level(nil), do: nil

  def uv_level(uv) when is_number(uv) do
    cond do
      uv < 3 -> l("Low")
      uv < 6 -> l("Moderate")
      uv < 8 -> l("High")
      uv < 11 -> l("Very High")
      true -> l("Extreme")
    end
  end

  def uv_level(_), do: nil

  @doc """
  Gets the UV index color class based on level.
  """
  def uv_color(nil), do: "text-base-content/70"

  def uv_color(uv) when is_number(uv) do
    cond do
      uv < 3 -> "text-success"
      uv < 6 -> "text-warning"
      uv < 8 -> "text-orange-500"
      true -> "text-error"
    end
  end

  def uv_color(_), do: "text-base-content/70"

  @doc """
  Formats humidity as percentage (API returns 0-1 value).
  """
  def format_humidity(nil), do: nil

  def format_humidity(humidity) when is_number(humidity) do
    # PirateWeather returns humidity as 0-1, convert to percentage
    if humidity <= 1 do
      round(humidity * 100)
    else
      round(humidity)
    end
  end

  def format_humidity(_), do: nil

  @doc """
  Formats temperature for display, rounding to integer.
  """
  def format_temp(nil), do: nil
  def format_temp(temp) when is_number(temp), do: round(temp)
  def format_temp(_), do: nil

  @doc """
  Formats wind speed for display.
  """
  def format_wind_speed(nil, _units), do: nil

  def format_wind_speed(speed, units) when is_number(speed) do
    rounded = round(speed)
    unit_label = if units == :imperial, do: "mph", else: "km/h"
    "#{rounded} #{unit_label}"
  end

  def format_wind_speed(_, _), do: nil

  @doc """
  Gets astronomical data (sunrise, sunset, moon phase) for coordinates.
  Returns a map with :sunrise, :sunset, :moon_phase, :moon_emoji keys.
  """
  def get_astro_data(nil, _date), do: %{}
  def get_astro_data(_coords, nil), do: %{}

  def get_astro_data(%{"lat" => lat, "lon" => lon}, date)
      when is_number(lat) and is_number(lon) do
    # Astro library accepts {longitude, latitude} tuple
    location = {lon, lat}
    # Custom timezone resolver that always returns UTC (since we don't have tz_world)
    utc_resolver = fn _location -> {:ok, "Etc/UTC"} end
    opts = [time_zone: :utc, time_zone_resolver: utc_resolver]

    sunrise = safe_astro_call(fn -> Astro.sunrise(location, date, opts) end)
    sunset = safe_astro_call(fn -> Astro.sunset(location, date, opts) end)
    # lunar_phase_at returns phase angle (0-360 degrees)
    phase_angle = safe_astro_call(fn -> Astro.lunar_phase_at(DateTime.utc_now()) end)
    # lunar_phase_emoji expects phase angle, not DateTime
    moon_emoji =
      if phase_angle, do: safe_astro_call(fn -> Astro.lunar_phase_emoji(phase_angle) end)

    %{
      sunrise: sunrise,
      sunset: sunset,
      moon_phase: phase_angle_to_name(phase_angle),
      moon_emoji: moon_emoji || "🌙"
    }
  end

  def get_astro_data(_, _), do: %{}

  defp safe_astro_call(fun) do
    try do
      case fun.() do
        {:ok, result} -> result
        {:error, _} -> nil
        result -> result
      end
    rescue
      _ -> nil
    end
  end

  @doc """
  Converts moon phase angle (0-360 degrees) to human-readable name.
  """
  def phase_angle_to_name(nil), do: nil

  def phase_angle_to_name(angle) when is_number(angle) do
    cond do
      angle < 22.5 or angle >= 337.5 -> l("New Moon")
      angle < 67.5 -> l("Waxing Crescent")
      angle < 112.5 -> l("First Quarter")
      angle < 157.5 -> l("Waxing Gibbous")
      angle < 202.5 -> l("Full Moon")
      angle < 247.5 -> l("Waning Gibbous")
      angle < 292.5 -> l("Last Quarter")
      true -> l("Waning Crescent")
    end
  end

  def phase_angle_to_name(_), do: nil

  @doc """
  Formats a DateTime or Time to a human-readable time string.
  """
  def format_time(nil), do: nil

  def format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%-I:%M %p")
  end

  def format_time(%Time{} = time) do
    Calendar.strftime(time, "%-I:%M %p")
  end

  def format_time(_), do: nil
end
