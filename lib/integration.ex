defmodule Bonfire.Geolocate do
  def is_admin?(user) do
    if Map.get(user, :instance_admin) do
      Map.get(user.instance_admin, :is_instance_admin)
    else
      # FIXME
      false
    end
  end
end
