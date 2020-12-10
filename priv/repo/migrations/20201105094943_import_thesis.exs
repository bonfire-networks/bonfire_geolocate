defmodule Bonfire.Geolocate.Repo.Migrations.ImportMe do
  use Ecto.Migration

  import Bonfire.Geolocate.Migration
  # accounts & users

  def change, do: migrate_thesis

end
