defmodule Bonfire.Geolocate.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  def config do
    import Config

    config :bonfire, :js_config,
      mapbox_api_key: Bonfire.Common.EnvSecrets.env_or_file("MAPBOX_API_KEY"),
      protomaps_api_key: Bonfire.Common.EnvSecrets.env_or_file("PROTOMAPS_API_KEY")

    config :bonfire, :ui,
      # activity_preview: [],
      object_preview: [
        {Bonfire.Geolocate.Geolocation, Bonfire.Geolocate.PlacePreviewLive}
      ]

    if api_key = Bonfire.Common.EnvSecrets.env_or_file("OPEN_WEATHER_MAP_API_KEY") do
      config :forecastr,
        backend: Forecastr.OWM,
        appid: api_key,
        # minutes to cache
        ttl: 14 * 60_000
    end

    if api_key = Bonfire.Common.EnvSecrets.env_or_file("PIRATE_WEATHER_API_KEY") do
      config :forecastr,
        backend: Forecastr.PirateWeather,
        appid: api_key,
        # minutes to cache
        ttl: 14 * 60_000
    end
  end
end
