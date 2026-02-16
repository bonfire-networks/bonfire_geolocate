defmodule Bonfire.Geolocate.Settings.WeatherBackendSettingLive do
  use Bonfire.UI.Common.Web, :stateless_component

  declare_settings(:select, l("Weather Service"),
    keys: [:forecastr, :backend],
    options: [
      "Forecastr.PirateWeather": l("PirateWeather"),
      "Forecastr.OWM": l("OpenWeatherMap"),
      "Forecastr.OpenMeteo": l("Open-Meteo (no key required)")
    ],
    default_value: "Forecastr.PirateWeather",
    description: l("Select which weather API backend to use."),
    scope: :instance
  )
end
