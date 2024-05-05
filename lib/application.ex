defmodule Bonfire.Geolocate do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  use Application

  def start(_type, _args) do
    children = [
      # See the documentation for tz_world for the various available backends. DetsWithIndexCache is the recommended backend for balancing speed and memory usage.
      TzWorld.Backend.DetsWithIndexCache
    ]

    opts = [strategy: :one_for_one, name: Bonfire.Geolocate.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
