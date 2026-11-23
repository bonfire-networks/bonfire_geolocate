defmodule Bonfire.Geolocate.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  The maps backend, from `MAPS_BACKEND` and `MAPBOX_API_KEY`, as `{backend, mapbox_api_key}`: `openfreemap` (the default: a server of map styles, `MAP_STYLES_URL`), `mapbox` (needs a key, which only then reaches the browser), or `none`. `mapbox` without a key, or an unknown value, warns and uses `openfreemap`.

      iex> maps_backend(nil, "pk.abc")
      {:openfreemap, nil}

      iex> maps_backend("mapbox", "pk.abc")
      {:mapbox, "pk.abc"}

      iex> maps_backend("mapbox", nil)
      {:openfreemap, nil}

      iex> maps_backend("none", "pk.abc")
      {:none, nil}

      iex> maps_backend("tomtom", nil)
      {:openfreemap, nil}
  """
  def maps_backend(backend, mapbox_api_key) do
    case {backend, mapbox_api_key} do
      {"mapbox", key} when is_binary(key) and key != "" ->
        {:mapbox, key}

      {"mapbox", _} ->
        IO.warn(
          "MAPS_BACKEND is mapbox but MAPBOX_API_KEY is not set, so maps use the default backend (openfreemap)",
          []
        )

        {:openfreemap, nil}

      {"none", _} ->
        {:none, nil}

      {default, _} when default in [nil, "", "openfreemap"] ->
        {:openfreemap, nil}

      {other, _} ->
        IO.warn(
          "MAPS_BACKEND #{inspect(other)} is not one of openfreemap, mapbox or none, so maps use the default backend (openfreemap)",
          []
        )

        {:openfreemap, nil}
    end
  end

  def config do
    import Config

    if System.get_env("DB_ADAPTER") == "yugabyte" do
      # YugabyteDB doesn't ship PostGIS, so the geolocation tables aren't created there (see Bonfire.Geolocate.Migrations)
      config :bonfire_geolocate, modularity: :disabled
    end

    # the maps backend (`MAPS_BACKEND`, see `maps_backend/2`): the Mapbox key reaches the browser (in `js_config`) only when Mapbox is chosen
    {maps_backend, mapbox_api_key} =
      maps_backend(
        System.get_env("MAPS_BACKEND"),
        Bonfire.Common.EnvSecrets.env_or_file("MAPBOX_API_KEY")
      )

    config :bonfire, :js_config, mapbox_api_key: mapbox_api_key

    # protomaps_api_key: Bonfire.Common.EnvSecrets.env_or_file("PROTOMAPS_API_KEY")
    # ^ Protomaps not currently used

    # the server of the map styles (vector tiles drawn by the browser) for the `openfreemap` backend: OpenFreeMap's, or a self-hosted one
    config :bonfire_geolocate, Bonfire.Geolocate,
      maps_backend: maps_backend,
      map_styles_url: System.get_env("MAP_STYLES_URL", "https://tiles.openfreemap.org/styles/")

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
