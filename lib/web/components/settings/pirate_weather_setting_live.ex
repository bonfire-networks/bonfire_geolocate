defmodule Bonfire.Geolocate.Settings.PirateWeatherSettingLive do
  use Bonfire.UI.Common.Web, :stateless_component

  declare_settings(:input, l("Pirate Weather API Key"),
    keys: [Bonfire.Geolocate, :pirate_weather_api_key],
    icon: "ph:globe-duotone",
    description: l("Enter your API key from pirateweather.net for the weather forecast widget")
  )
end
