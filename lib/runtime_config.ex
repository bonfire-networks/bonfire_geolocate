defmodule Bonfire.Geolocate.RuntimeConfig do
  def config_module, do: true

  def config do
    import Config

    config :bonfire, :js_config, mapbox_api_key: System.get_env("MAPBOX_API_KEY")
  end
end