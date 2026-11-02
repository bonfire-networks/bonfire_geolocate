defmodule Bonfire.Geolocate do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  use Application

  def start(_type, _args) do
    children = [
      # See the documentation for tz_world for the various available backends. SpatialIndex is the default since tz_world 2.4, and `mix tz_world.update` only builds its data unless asked for others.
      # TzWorld.Backend.DetsWithIndexCache # deprecated in tz_world 2.4
      TzWorld.Backend.SpatialIndex
    ]

    opts = [strategy: :one_for_one, name: Bonfire.Geolocate.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
