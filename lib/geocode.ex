defmodule Bonfire.Geolocate.Geocode do

  def coordinates(query) do
    # use the default provider (OpenStreetMaps)
    with {:error, _} <- maybe_with_geocoder(query),
    # use an alternative provider. If `key` is not specified here the globally defined key will be used.
    {:error, _} <- maybe_with_opencage(query) do
      {:error, nil}
    end
  end

  defp maybe_with_geocoder(query) do
    Geocoder.call(query)
  catch _ ->
    {:error, nil}
  end

  defp maybe_with_opencage(query) do
    key = System.get_env("GEOLOCATE_OPENCAGEDATA")
    if key && key !="" do
      Geocoder.call(query, provider: Geocoder.Providers.OpenCageData, key: key)
    else
      {:error, nil}
    end
  end

end
