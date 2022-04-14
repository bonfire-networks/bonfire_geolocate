defmodule Bonfire.Geolocate.Geocode do
  import Where

  def coordinates(query) do
    # use the default provider (OpenStreetMaps)
    with {:error, _} <- maybe_with_geocoder(query),
    # use an alternative provider. If `key` is not specified here the globally defined key will be used.
    {:error, _} <- maybe_with_opencage(query) do
      {:error, nil}
    end
  catch
    :exit, error ->
      error(__STACKTRACE__, inspect error)
      {:error, error}
  end

  defp maybe_with_geocoder(query) do
    Geocoder.call(query)
  end

  defp maybe_with_opencage(query) do
    key = System.get_env("GEOLOCATE_OPENCAGEDATA")
    if key && key !="" do
      Geocoder.call(query, provider: Geocoder.Providers.OpenCageData, key: key)
    else
      error("You need to configure an API key for https://opencagedata.com in env: GEOLOCATE_OPENCAGEDATA")
      {:error, "No API"}
    end
  end

end
