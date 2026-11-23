defmodule Bonfire.Geolocate.ViewerLocationTest do
  @moduledoc "Where the viewer is, for \"nearby\": their location setting (as coordinates, or text to geocode), else the profile's own location text. The browser's location is saved to the setting only, never to the profile."
  use Bonfire.Geolocate.DataCase, async: true

  import Bonfire.Me.Fake
  use Bonfire.Common.Settings
  alias Bonfire.Geolocate.ViewerLocation

  # a geocoder that must not be called
  defp no_geocoding(_), do: raise("geocoded when it should not have been")

  defp geocoding(%{} = results), do: fn text -> Map.get(results, text, {:error, nil}) end

  # the user struct carries its settings, so read them again after a change
  defp reload_settings(user), do: Bonfire.Common.Repo.maybe_preload(user, :settings, force: true)

  defp with_location_setting(user, text) do
    {:ok, _} =
      Settings.put([Bonfire.Geolocate, :location], text, current_user: user, scope: :user)

    reload_settings(user)
  end

  defp resolve(user, opts), do: ViewerLocation.resolve([current_user: user], opts)

  defp user_with_profile_location(location) do
    # the fake profile form takes its fields from the top level of the attrs
    fake_user!(fake_account!(), %{location: location})
  end

  test "coordinates are read from \"lat,long\" and rounded to 3 decimals; text and impossible numbers are not coordinates" do
    assert ViewerLocation.parse("50.432,-3.684") == %{lat: 50.432, long: -3.684}
    assert ViewerLocation.parse(" 50.4319 , -3.6837 ") == %{lat: 50.4319, long: -3.6837}
    assert ViewerLocation.parse("Totnes, UK") == nil
    assert ViewerLocation.parse("95.0,10.0") == nil
    assert ViewerLocation.parse("10.0,190.0") == nil
    assert ViewerLocation.parse(nil) == nil

    assert ViewerLocation.format(50.43189, -3.68371) == "50.432,-3.684"
  end

  test "the setting's coordinates come first, and nothing is geocoded for them" do
    user = user_with_profile_location("Paris, France") |> with_location_setting("50.432,-3.684")

    assert resolve(user, geocode: &no_geocoding/1) ==
             %{lat: 50.432, long: -3.684, source: :setting, name: nil}
  end

  test "a place name saved with the coordinates comes back with them, and a later save without one clears it" do
    user = user_with_profile_location(nil)

    assert {:ok, %{lat: 50.432, long: -3.684}} =
             ViewerLocation.save([current_user: user], 50.43189, -3.68371, "Totnes")

    user = reload_settings(user)

    assert resolve(user, geocode: &no_geocoding/1) ==
             %{lat: 50.432, long: -3.684, source: :setting, name: "Totnes"}

    assert {:ok, _} = ViewerLocation.save([current_user: user], 51.5, -0.12)
    user = reload_settings(user)

    assert resolve(user, geocode: &no_geocoding/1) ==
             %{lat: 51.5, long: -0.12, source: :setting, name: nil}
  end

  test "the profile's text is the name of a point found from it, and a text setting is its own name" do
    user = user_with_profile_location("Paris, France")
    geocode = geocoding(%{"Paris, France" => {:ok, %{lat: 48.85, lon: 2.35}}})
    assert %{name: "Paris, France"} = resolve(user, geocode: geocode)
  end

  test "a setting that is text is geocoded, before the profile's location" do
    user = user_with_profile_location("Paris, France") |> with_location_setting("Totnes")

    geocode =
      geocoding(%{
        "Totnes" => {:ok, %{lat: 50.43, lon: -3.68}},
        "Paris, France" => {:ok, %{lat: 48.85, lon: 2.35}}
      })

    assert resolve(user, geocode: geocode) ==
             %{lat: 50.43, long: -3.68, source: :setting, name: "Totnes"}
  end

  test "without a setting, the profile's own location text is geocoded; without either, nothing" do
    user = user_with_profile_location("Paris, France")
    geocode = geocoding(%{"Paris, France" => {:ok, %{lat: 48.85, lon: 2.35}}})

    assert resolve(user, geocode: geocode) ==
             %{lat: 48.85, long: 2.35, source: :profile, name: "Paris, France"}

    assert resolve(user, geocode: geocoding(%{})) == nil
    assert resolve(user_with_profile_location(nil), geocode: &no_geocoding/1) == nil
  end

  test "saving a browser location writes the rounded coordinates to the setting, and not to the profile" do
    user = user_with_profile_location("Paris, France")

    assert {:ok, %{lat: 50.432, long: -3.684}} =
             ViewerLocation.save([current_user: user], 50.43189, -3.68371)

    # read back as the user would see it, in a fresh context
    user = reload_settings(user)

    assert Settings.get([Bonfire.Geolocate, :location], nil, current_user: user) ==
             "50.432,-3.684"

    assert resolve(user, geocode: &no_geocoding/1) ==
             %{lat: 50.432, long: -3.684, source: :setting, name: nil}

    # the profile's location is only read, never written
    assert user.profile.location == "Paris, France"

    assert Bonfire.Common.Repo.maybe_preload(user, :profile, force: true).profile.location ==
             "Paris, France"
  end
end
