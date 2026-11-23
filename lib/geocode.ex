defmodule Bonfire.Geolocate.Geocode do
  import Untangle

  def coordinates(query) do
    if geocoder_running?() do
      # use the default provider (OpenStreetMaps)
      with {:error, _} <- maybe_with_geocoder(query),
           # use an alternative provider. If `key` is not specified here the globally defined key will be used.
           {:error, _} <- maybe_with_opencage(query) do
        {:error, nil}
      end
    else
      error("The geocoder's worker pool is not running, so #{inspect(query)} was not geocoded")
      {:error, :geocoder_not_running}
    end
  catch
    :exit, error ->
      error(__STACKTRACE__, inspect(error))
      {:error, error}
  end

  @doc "The name of the place at a point (its city, else county, state or country), or nil. One call to the geocoder, so keep the result rather than call this on each render."
  def place_name(lat, long) when is_number(lat) and is_number(long) do
    with true <- geocoder_running?(),
         {:ok, %{location: %{} = location}} <- Geocoder.call({lat, long}) do
      [:city, :county, :state, :country]
      |> Enum.find_value(fn key ->
        case Map.get(location, key) do
          name when is_binary(name) and name != "" -> name
          _ -> nil
        end
      end)
    else
      _ -> nil
    end
  catch
    :exit, error ->
      error(__STACKTRACE__, inspect(error))
      nil
  end

  defp geocoder_running?, do: not is_nil(Process.whereis(Geocoder.Config.default_pool_name()))

  defp maybe_with_geocoder(query) do
    Geocoder.call(query)
  end

  defp maybe_with_opencage(query) do
    key = System.get_env("GEOLOCATE_OPENCAGEDATA")

    if key && key != "" do
      Geocoder.call(query, provider: Geocoder.Providers.OpenCageData, key: key)
    else
      error(
        "You need to configure an API key for https://opencagedata.com in env: GEOLOCATE_OPENCAGEDATA"
      )

      {:error, "No API"}
    end
  end
end
