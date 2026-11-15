defmodule Bonfire.Geolocate.CreateRedirectTest do
  @moduledoc """
  After creating a place the user is sent on to a page. A `redirect_after` value that comes from the request must never send the user to another site.
  """
  use Bonfire.Geolocate.ConnCase, async: false

  import Bonfire.UI.Common.Testing.Helpers, only: [conn: 1]

  setup do
    :meck.new(Bonfire.Geolocate.Geocode, [:passthrough, :no_link])
    :meck.expect(Bonfire.Geolocate.Geocode, :coordinates, fn _query -> {:error, nil} end)
    on_exit(fn -> :meck.unload(Bonfire.Geolocate.Geocode) end)

    account = fake_account!()

    {:ok,
     account: account,
     user: fake_user!(account),
     name: "Redirect Place #{System.unique_integer([:positive])}"}
  end

  # where the signed-in user's socket is sent after the event
  defp redirect_target(ctx, redirect_after) do
    {:ok, view, _html} = live(conn(user: ctx.user, account: ctx.account), "/feed")

    result =
      render_hook(view, "Bonfire.Geolocate:create", %{
        "name" => ctx.name,
        "redirect_after" => redirect_after
      })

    case result do
      {:error, {_kind, %{to: to}}} -> to
      _ -> nil
    end
  end

  test "a signed-in user is sent on to a local page after creating a place (control)", ctx do
    assert "/geolocation/" <> _ = redirect_target(ctx, "/geolocation")
  end

  test "a signed-in user is not sent to another site after creating a place", ctx do
    target = redirect_target(ctx, "https://evil.local/x")

    refute is_binary(target) and String.contains?(target, "evil.local")
  end
end
