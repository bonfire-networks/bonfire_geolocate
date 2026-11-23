defmodule Bonfire.Geolocate.Settings.MapStyleSettingLive do
  use Bonfire.UI.Common.Web, :stateless_component

  # an instance's default, and each user's choice (the settings cascade); the styles offered are in config
  declare_settings(:select, l("Map style"),
    keys: [Bonfire.Geolocate, :map_style],
    options: Bonfire.Geolocate.MapLive.map_styles(),
    default_value: :liberty,
    icon: "ph:map-pin-duotone",
    description:
      l("How maps look (when the instance uses a server of map styles, eg. OpenFreeMap).")
  )
end
