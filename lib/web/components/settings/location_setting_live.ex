defmodule Bonfire.Geolocate.Settings.LocationSettingLive do
  use Bonfire.UI.Common.Web, :stateless_component

  declare_settings(:input, l("Location"),
    keys: [Bonfire.Geolocate, :location],
    icon: "ph:globe-duotone",
    description: l("Set your location to display weather on your dashboard.")
    # scope: :user
  )
end
