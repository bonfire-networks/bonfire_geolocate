defmodule Bonfire.Geolocate.FeedFilterNearbyTest do
  @moduledoc "The feed filter editor's \"Nearby\" row, as geolocate's own control: a radius around the viewer's location, which comes from their location setting, else their profile's location text, else the browser (saved to the setting by the \"Detect location\" button, never to the profile). The events reach `Bonfire.Geolocate.LiveHandler` with the editor's own socket and change the editor's pending filters."
  # `@moduletag :ui` comes with this case
  use Bonfire.Geolocate.ConnCase, async: false

  use Bonfire.Common.Settings
  alias Bonfire.Geolocate.LiveHandler
  alias Bonfire.Geolocate.ViewerLocation
  alias Bonfire.UI.Social.FeedFiltersModalContentLive, as: Editor

  defp editor(user, filters \\ %{}, extra \\ %{}) do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, __context__: %{current_user: user}}
    }

    {:ok, socket} =
      Editor.update(
        Map.merge(
          %{id: "draft", feed_filters: filters, context_key: :local, apply_to: :parent},
          extra
        ),
        socket
      )

    socket
  end

  defp applied(socket) do
    {:noreply, _socket} = Editor.handle_event("apply", %{}, socket)
    assert_received {Editor, :apply, filters}
    filters
  end

  defp user_without_location, do: fake_user!(fake_account!(), %{location: nil})

  defp no_geocoding(_), do: raise("geocoded when it should not have been")

  defp reload_settings(user), do: Bonfire.Common.Repo.maybe_preload(user, :settings, force: true)

  defp saved_location(user),
    do: ViewerLocation.resolve([current_user: reload_settings(user)], geocode: &no_geocoding/1)

  test "a location from the browser is rounded, saved with its place name to the location setting only, and turns the filter on" do
    user = fake_user!(fake_account!(), %{location: "Paris, France"})
    reverse = fn lat, long -> if {lat, long} == {50.432, -3.684}, do: "Totnes" end

    {:noreply, socket} =
      LiveHandler.handle_event(
        "set_location",
        %{"lat" => 50.43189, "long" => -3.68371},
        editor(user, %{}, %{reverse_geocode: reverse})
      )

    assert applied(socket)[:nearby] ==
             %{lat: 50.432, long: -3.684, km: 25, include_no_place: true}

    assert saved_location(user) ==
             %{lat: 50.432, long: -3.684, source: :setting, name: "Totnes"}

    # the profile's own location is left alone
    assert Bonfire.Common.Repo.maybe_preload(user, :profile, force: true).profile.location ==
             "Paris, France"
  end

  test "a place name that cannot be found is not needed to save the location" do
    user = user_without_location()

    {:noreply, socket} =
      LiveHandler.handle_event(
        "set_location",
        %{"lat" => 50.4, "long" => -3.6},
        editor(user, %{}, %{reverse_geocode: fn _, _ -> nil end})
      )

    assert applied(socket)[:nearby].lat == 50.4
    assert %{lat: 50.4, long: -3.6, name: nil} = saved_location(user)
  end

  test "a radius chosen before is kept when the location is detected again" do
    user = user_without_location()
    filters = %{nearby: %{lat: 10.0, long: 20.0, km: 50, include_no_place: false}}

    {:noreply, socket} =
      LiveHandler.handle_event(
        "set_location",
        %{"lat" => "50.4", "long" => "-3.6"},
        editor(user, filters, %{reverse_geocode: fn _, _ -> nil end})
      )

    assert applied(socket)[:nearby] ==
             %{lat: 50.4, long: -3.6, km: 50, include_no_place: false}
  end

  test "the radius, \"also show things with no place\" and off, once there is a location" do
    user = user_without_location()

    {:noreply, socket} =
      LiveHandler.handle_event(
        "set_location",
        %{"lat" => 50.4, "long" => -3.6},
        editor(user, %{}, %{reverse_geocode: fn _, _ -> nil end})
      )

    {:noreply, socket} =
      LiveHandler.handle_event(
        "set_nearby",
        %{"radius" => "100", "include_no_place" => "false"},
        socket
      )

    assert applied(socket)[:nearby] == %{lat: 50.4, long: -3.6, km: 100, include_no_place: false}

    {:noreply, socket} =
      LiveHandler.handle_event(
        "set_nearby",
        %{"radius" => "5", "include_no_place" => "true"},
        socket
      )

    assert applied(socket)[:nearby] == %{lat: 50.4, long: -3.6, km: 5, include_no_place: true}

    # off is applied as an explicit nil, as the host merges what's applied into the filters it has
    {:noreply, socket} = LiveHandler.handle_event("set_nearby", %{"radius" => ""}, socket)
    assert Map.fetch(applied(socket), :nearby) == {:ok, nil}
  end

  test "an imperial viewer picks miles, which are set on the filter as kilometres" do
    user = user_without_location()
    {:ok, _} = Settings.put(:measurement_units, :imperial, current_user: user, scope: :user)
    # a put starts from the settings the user was loaded with
    user = reload_settings(user)

    {:ok, _} =
      Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
        current_user: user,
        scope: :user
      )

    user = reload_settings(user)

    {:noreply, socket} = LiveHandler.handle_event("set_nearby", %{"radius" => "10"}, editor(user))
    assert %{km: km, lat: 50.432, long: -3.684} = applied(socket)[:nearby]
    assert_in_delta km, 16.09, 0.01

    # and a metric viewer's number is kilometres as it is
    metric = user_without_location()

    {:ok, _} =
      Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
        current_user: metric,
        scope: :user
      )

    {:noreply, socket} =
      LiveHandler.handle_event("set_nearby", %{"radius" => "10"}, editor(reload_settings(metric)))

    assert applied(socket)[:nearby].km == 10
  end

  test "without a location the filter can't be set: the control shows only the button until one is found" do
    user = user_without_location()
    socket = editor(user, %{}, %{geocode: fn _ -> {:error, nil} end})

    {:noreply, socket} = LiveHandler.handle_event("set_nearby", %{"radius" => "25"}, socket)
    refute Map.get(applied(socket), :nearby)
  end

  test "a location setting is used as it is, without geocoding" do
    user = user_without_location()

    {:ok, _} =
      Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
        current_user: user,
        scope: :user
      )

    user = reload_settings(user)

    socket = editor(user, %{}, %{geocode: &no_geocoding/1})

    {:noreply, socket} = LiveHandler.handle_event("set_nearby", %{"radius" => "10"}, socket)

    assert applied(socket)[:nearby] == %{
             lat: 50.432,
             long: -3.684,
             km: 10,
             include_no_place: true
           }
  end

  test "the point already on the filter is kept when there is no location, as a saved feed needs" do
    user = user_without_location()
    filters = %{nearby: %{lat: 10.0, long: 20.0, km: 50, include_no_place: true}}

    {:noreply, socket} =
      LiveHandler.handle_event("set_nearby", %{"radius" => "5"}, editor(user, filters))

    assert applied(socket)[:nearby] == %{lat: 10.0, long: 20.0, km: 5, include_no_place: true}
  end

  test "the profile's location text is geocoded once, when the row is first opened, and kept with its name in the setting" do
    user = fake_user!(fake_account!(), %{location: "Paris, France"})
    test_pid = self()

    geocode = fn text ->
      send(test_pid, {:geocoded, text})
      {:ok, %{lat: 48.85, lon: 2.35}}
    end

    socket = editor(user, %{}, %{geocode: geocode})
    refute_received {:geocoded, _}

    {:noreply, socket} = LiveHandler.handle_event("locate", %{}, socket)
    assert_received {:geocoded, "Paris, France"}
    assert socket.assigns.control_state[:nearby][:checked?]

    {:noreply, _socket} = LiveHandler.handle_event("locate", %{}, socket)
    refute_received {:geocoded, _}

    # the point is kept in the user's own location setting, so it is not geocoded again: the setting is used first from now on (the profile is left as it is)
    saved = reload_settings(user)
    assert Settings.get([Bonfire.Geolocate, :location], nil, current_user: saved) == "48.85,2.35"

    assert saved_location(user) ==
             %{lat: 48.85, long: 2.35, source: :setting, name: "Paris, France"}

    assert Bonfire.Common.Repo.maybe_preload(user, :profile, force: true).profile.location ==
             "Paris, France"
  end

  describe "a typed place" do
    test "is geocoded and used for this search only: the saved location stays as it is" do
      user = user_without_location()

      {:ok, _} =
        Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
          current_user: user,
          scope: :user
        )

      user = reload_settings(user)

      geocode = fn
        "Plymouth" -> {:ok, %{lat: 50.3756, lon: -4.1427}}
        _ -> {:error, nil}
      end

      socket = editor(user, %{}, %{geocode: geocode})
      {:noreply, socket} = LiveHandler.handle_event("set_nearby", %{"radius" => "10"}, socket)

      {:noreply, socket} =
        LiveHandler.handle_event("set_place", %{"place" => " Plymouth "}, socket)

      assert applied(socket)[:nearby] ==
               %{lat: 50.376, long: -4.143, km: 10, include_no_place: true}

      assert socket.assigns.control_state[:nearby][:place] ==
               %{name: "Plymouth", lat: 50.376, long: -4.143}

      assert saved_location(user) == %{lat: 50.432, long: -3.684, source: :setting, name: nil}

      # and a radius change afterwards keeps the typed place
      {:noreply, socket} = LiveHandler.handle_event("set_nearby", %{"radius" => "50"}, socket)

      assert applied(socket)[:nearby] == %{
               lat: 50.376,
               long: -4.143,
               km: 50,
               include_no_place: true
             }
    end

    test "with no saved location sets the pending point for this search only, and saves nothing" do
      user = user_without_location()

      socket =
        editor(user, %{}, %{geocode: fn "Plymouth" -> {:ok, %{lat: 50.3756, lon: -4.1427}} end})

      {:noreply, socket} = LiveHandler.handle_event("set_place", %{"place" => "Plymouth"}, socket)

      assert applied(socket)[:nearby] ==
               %{lat: 50.376, long: -4.143, km: 25, include_no_place: true}

      assert socket.assigns.control_state[:nearby][:place] ==
               %{name: "Plymouth", lat: 50.376, long: -4.143}

      assert saved_location(user) == nil
    end

    test "that cannot be found changes nothing, and says so" do
      user = user_without_location()
      filters = %{nearby: %{lat: 10.0, long: 20.0, km: 50, include_no_place: true}}
      socket = editor(user, filters, %{geocode: fn _ -> {:error, nil} end})

      {:noreply, socket} =
        LiveHandler.handle_event("set_place", %{"place" => "Nowhereville"}, socket)

      assert applied(socket)[:nearby] == filters.nearby
      assert socket.assigns.control_state[:nearby][:place_not_found]
    end

    test "emptied goes back to the saved location, and drops the typed one" do
      user = user_without_location()

      {:ok, _} =
        Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
          current_user: user,
          scope: :user
        )

      user = reload_settings(user)
      socket = editor(user, %{}, %{geocode: fn _ -> {:ok, %{lat: 1.0, lon: 2.0}} end})

      {:noreply, socket} =
        LiveHandler.handle_event("set_place", %{"place" => "Somewhere"}, socket)

      assert applied(socket)[:nearby].lat == 1.0

      {:noreply, socket} = LiveHandler.handle_event("set_place", %{"place" => ""}, socket)
      assert %{lat: 50.432, long: -3.684} = applied(socket)[:nearby]
      refute socket.assigns.control_state[:nearby][:place]
    end
  end

  test "through the real funnel, the prefixed event ends in the same pending filters" do
    user = user_without_location()

    {:ok, _} =
      Settings.put([Bonfire.Geolocate, :location], "50.432,-3.684",
        current_user: user,
        scope: :user
      )

    socket = editor(reload_settings(user))

    {:noreply, socket} =
      Bonfire.UI.Common.LiveHandlers.handle_event(
        "Bonfire.Geolocate:set_nearby",
        %{"radius" => "10"},
        socket
      )

    assert applied(socket)[:nearby] == %{
             lat: 50.432,
             long: -3.684,
             km: 10,
             include_no_place: true
           }
  end

  test "a guest cannot save a location through the funnel" do
    socket = editor(nil)
    socket = %{socket | assigns: Map.put(socket.assigns, :flash, %{})}

    result =
      Bonfire.UI.Common.LiveHandlers.handle_event(
        "Bonfire.Geolocate:set_location",
        %{"lat" => 50.4, "long" => -3.6},
        socket
      )

    refute match?(%{nearby: %{lat: _}}, pending_filters(result))
  end

  defp pending_filters({:noreply, socket}), do: socket.assigns[:pending_filters]
  defp pending_filters(_), do: %{}
end
