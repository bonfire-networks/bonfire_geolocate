defmodule Bonfire.Geolocate.PlacePreviewHostileTextTest do
  @moduledoc """
  The name of a place is written by a user and kept as received, so it must never come out as raw HTML.
  """
  use ExUnit.Case, async: true
  use Surface.LiveViewTest

  # bare `ExUnit.Case` skips the tag the extension case templates apply, so without this it also runs in the federation CI leg
  @moduletag :ui

  alias Bonfire.Geolocate.PlacePreviewLive

  @payload "<img src=x onerror=alert(1)>"

  defp live_onerror?(html), do: html =~ ~r/<img[^>]*onerror/i

  defp render_place(attrs) do
    assigns = %{
      place: Map.merge(%{id: "01HZZ0PlaceTEST", name: "Town hall", lat: 1.0, long: 2.0}, attrs)
    }

    render_surface do
      ~F"""
      <PlacePreviewLive object={@place} parent_id="place-test" />
      """
    end
  end

  test "a hostile name renders without a live onerror" do
    refute live_onerror?(render_place(%{name: @payload}))
  end

  test "a hostile summary renders without a live onerror" do
    refute live_onerror?(render_place(%{summary: @payload}))
  end

  test "a plain name is shown (control)" do
    assert render_place(%{name: "Library"}) =~ "Library"
  end
end
