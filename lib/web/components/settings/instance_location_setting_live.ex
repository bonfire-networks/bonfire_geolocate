defmodule Bonfire.Geolocate.Settings.InstanceLocationSettingLive do
  use Bonfire.UI.Common.Web, :stateless_component

  declare_settings(:input, l("Location"),
    keys: [Bonfire.Geolocate, :location],
    icon: "ph:globe-duotone",
    description: l("Set a default location (used for weather on the dashboard when a user hasn't set their own)."),
    scope: :instance
  )
end
