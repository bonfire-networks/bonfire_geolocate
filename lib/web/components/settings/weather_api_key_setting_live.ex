defmodule Bonfire.Geolocate.Settings.WeatherApiKeySettingLive do
  use Bonfire.UI.Common.Web, :stateless_component

  declare_settings(:input, l("Weather API Key"),
    keys: [:forecastr, :appid],
    description:
      l(
        "API key for PirateWeather or OpenWeatherMap. Can also be set via PIRATE_WEATHER_API_KEY or OPEN_WEATHER_MAP_API_KEY environment variables."
      ),
    scope: :instance
  )
end
