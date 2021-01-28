defmodule Bonfire.Geolocate.Geocode do

  def coordinates(query) do
    # use the default provider (OpenStreetMaps)
    with {:error, nil} <- Geocoder.call(query),
    # use an alternative provider. If `key` is not specified here the globally defined key will be used.
    {:error, nil} <- maybe_call_opencage(query) do
      {:error, nil}
    end
  end

  def maybe_call_opencage(query) do
    key = System.get_env("GEOLOCATE_OPENCAGEDATA")
    if key do
      Geocoder.call(query, provider: Geocoder.Providers.OpenCageData, key: key)
    else
      {:error, nil}
    end
  end

end
