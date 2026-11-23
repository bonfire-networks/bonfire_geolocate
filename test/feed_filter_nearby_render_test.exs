defmodule Bonfire.Geolocate.FeedFilterNearbyRenderTest do
  @moduledoc "What the feed filter editor's \"Nearby\" row shows: the declaration, the summary and radius choices in the viewer's units, the controls hidden until there is a location, the editable place name, and the prefixed events that reach this extension's handler."
  # `@moduletag :ui` comes with this case
  use Bonfire.Geolocate.ConnCase, async: false

  use Bonfire.Common.Settings
  alias Bonfire.Geolocate.FeedFilterNearbyLive
  alias Bonfire.UI.Common.FeedFilterControlModule

  defp user_with(settings \\ []) do
    user = fake_user!(fake_account!(), %{location: nil})

    # a put starts from the settings the user was loaded with, so read them again after each
    Enum.reduce(settings, user, fn {keys, value}, user ->
      {:ok, _} = Settings.put(keys, value, current_user: user, scope: :user)
      Bonfire.Common.Repo.maybe_preload(user, :settings, force: true)
    end)
  end

  defp row(user, opts \\ []) do
    render_component(
      &FeedFilterNearbyLive.render/1,
      %{
        id: "ed",
        target: "#editor",
        feed_filters: opts[:filters] || %{},
        control_state: opts[:control_state] || %{},
        __context__: %{current_user: user}
      }
    )
    |> Floki.parse_fragment!()
  end

  @coords [{[Bonfire.Geolocate, :location], "50.432,-3.684"}]

  test "it declares itself as the control for the nearby filter, after Happening" do
    assert %{
             name: :nearby,
             module: FeedFilterNearbyLive,
             filters: [nearby: nil],
             after: :happening
           } =
             FeedFilterControlModule.declared(FeedFilterNearbyLive)
  end

  test "it is among the controls found at runtime" do
    assert :nearby in Enum.map(FeedFilterControlModule.controls(), & &1.name)
  end

  describe "with no location" do
    test "the place input and the icon-only Detect location button show; no radius, no checkbox" do
      html = row(user_with())

      assert [_] = Floki.find(html, "[data-row=nearby]")
      assert [place] = Floki.find(html, "input[name=place]")
      assert Floki.attribute(place, "value") in [[], [""]]
      assert Floki.attribute(place, "placeholder") == ["Type a place or detect your location"]

      assert [button] = Floki.find(html, "button[data-role=detect_location]")
      assert Floki.attribute(button, "aria-label") == ["Detect location"]
      assert Floki.attribute(button, "title") == ["Detect location"]
      assert [_] = Floki.find(button, "[iconify]")
      refute Floki.text(button) =~ "Detect location"

      # the button is on the same row as the input, inside the place form
      assert [_] =
               Floki.find(
                 html,
                 "form[phx-submit='Bonfire.Geolocate:set_place'] button[data-role=detect_location]"
               )

      assert [] = Floki.find(html, "select[name=radius]")
      assert [] = Floki.find(html, "input[name=include_no_place][type=checkbox]")
      assert Floki.find(html, "[data-role=row_value]") |> Floki.text() =~ "Anywhere"
    end
  end

  describe "with a location" do
    test "the radius, the checkbox ticked by default, and the place name field show" do
      user = user_with([{[Bonfire.Geolocate, :location_name], "Totnes"} | @coords])
      html = row(user)

      assert [_] = Floki.find(html, "select[name=radius]")
      assert [button] = Floki.find(html, "button[data-role=detect_location]")
      assert Floki.attribute(button, "aria-label") == ["Detect location"]

      assert [checkbox] = Floki.find(html, "input[name=include_no_place][type=checkbox]")
      assert Floki.attribute(checkbox, "checked") != []
      assert Floki.text(html) =~ "Also show online events and anything with no place specified"

      assert [place] = Floki.find(html, "input[name=place]")
      assert Floki.attribute(place, "value") == ["Totnes"]
    end

    test "the row is open when a radius is set, closed for Anywhere" do
      filters = %{nearby: %{lat: 50.432, long: -3.684, km: 50, include_no_place: true}}

      assert [details] =
               row(user_with(@coords), filters: filters) |> Floki.find("details[data-row=nearby]")

      assert Floki.attribute(details, "open") != []

      assert [details] = row(user_with(@coords)) |> Floki.find("details[data-row=nearby]")
      assert Floki.attribute(details, "open") == []
    end

    test "the checkbox is unticked for the strict filter" do
      filters = %{nearby: %{lat: 50.432, long: -3.684, km: 10, include_no_place: false}}
      html = row(user_with(@coords), filters: filters)

      assert [checkbox] = Floki.find(html, "input[name=include_no_place][type=checkbox]")
      assert Floki.attribute(checkbox, "checked") == []
    end

    test "the summary and the radius choices are in kilometres by default" do
      filters = %{nearby: %{lat: 50.432, long: -3.684, km: 10, include_no_place: true}}
      html = row(user_with(@coords), filters: filters)

      assert Floki.find(html, "[data-role=row_value]") |> Floki.text() =~ "Within 10 km"
      options = Floki.find(html, "select[name=radius] option")

      assert Enum.map(options, &(Floki.attribute(&1, "value") |> hd())) == [
               "",
               "5",
               "10",
               "25",
               "50",
               "100"
             ]

      assert Floki.text(options) =~ "Within 100 km"
      assert [selected] = Floki.find(html, "select[name=radius] option[selected]")
      assert Floki.attribute(selected, "value") == ["10"]
    end

    test "the summary and the radius choices are in miles for an imperial viewer, converted back from kilometres" do
      user = user_with([{:measurement_units, :imperial} | @coords])
      filters = %{nearby: %{lat: 50.432, long: -3.684, km: 16.09, include_no_place: true}}
      html = row(user, filters: filters)

      assert Floki.find(html, "[data-role=row_value]") |> Floki.text() =~ "Within 10 mi"
      options = Floki.find(html, "select[name=radius] option")

      assert Enum.map(options, &(Floki.attribute(&1, "value") |> hd())) == [
               "",
               "5",
               "10",
               "25",
               "50",
               "100"
             ]

      assert Floki.text(options) =~ "Within 100 mi"
      refute Floki.text(options) =~ " km"
      assert [selected] = Floki.find(html, "select[name=radius] option[selected]")
      assert Floki.attribute(selected, "value") == ["10"]
    end

    test "a typed place's name is shown while it is the point of the search, else the saved name" do
      user = user_with([{[Bonfire.Geolocate, :location_name], "Totnes"} | @coords])

      typed = %{nearby: %{lat: 50.376, long: -4.143, km: 10, include_no_place: true}}
      state = %{nearby: %{place: %{name: "Plymouth", lat: 50.376, long: -4.143}}}

      assert [place] =
               row(user, filters: typed, control_state: state) |> Floki.find("input[name=place]")

      assert Floki.attribute(place, "value") == ["Plymouth"]

      # the search moved back to the saved point (eg. by Detect location): the typed name no longer applies
      saved = %{nearby: %{lat: 50.432, long: -3.684, km: 10, include_no_place: true}}

      assert [place] =
               row(user, filters: saved, control_state: state) |> Floki.find("input[name=place]")

      assert Floki.attribute(place, "value") == ["Totnes"]
    end

    test "a place that was not found is said so" do
      state = %{nearby: %{place_not_found: true}}
      html = row(user_with(@coords), control_state: state)
      assert [_] = Floki.find(html, "[data-role=place_not_found]")
      assert [] = row(user_with(@coords)) |> Floki.find("[data-role=place_not_found]")
    end
  end

  test "its events carry this extension's prefix and target the editor" do
    html = row(user_with(@coords))

    assert [_] =
             Floki.find(
               html,
               "summary[phx-click='Bonfire.Geolocate:locate'][phx-target='#editor']"
             )

    assert [_] =
             Floki.find(
               html,
               "form[phx-change='Bonfire.Geolocate:set_nearby'][phx-target='#editor']"
             )

    assert [_] =
             Floki.find(
               html,
               "form[phx-submit='Bonfire.Geolocate:set_place'][phx-target='#editor']"
             )
  end

  test "the Detect location button sits in the element that has the hook, with its messages" do
    html = row(user_with())
    assert [hooked] = Floki.find(html, "[data-row=nearby] [phx-hook]")
    assert Floki.attribute(hooked, "data-denied") != []
    assert Floki.attribute(hooked, "data-unsupported") != []
    assert [_] = Floki.find(hooked, "[data-role=detect_location]")
  end

  test "the place form has no Enter hint, and a Search here submit button that starts hidden" do
    html = row(user_with())

    refute Floki.text(html) =~ "Press Enter to search there"

    assert [button] =
             Floki.find(
               html,
               "form[phx-submit='Bonfire.Geolocate:set_place'] button[type=submit][data-role=search_place]"
             )

    assert Floki.attribute(button, "aria-label") == ["Search here"]
    assert Floki.attribute(button, "title") == ["Search here"]

    assert button
           |> Floki.attribute("class")
           |> Enum.join(" ")
           |> String.split()
           |> Enum.member?("hidden")

    assert [_] = Floki.find(button, "[iconify]")
    refute Floki.text(button) =~ "Search here"
  end

  test "a guest gets no Nearby row" do
    assert [] = row(nil) |> Floki.find("[data-row=nearby]")
  end
end
