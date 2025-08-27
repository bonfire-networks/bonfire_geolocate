defmodule Bonfire.Geolocate.WidgetForecastLive do
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
end
