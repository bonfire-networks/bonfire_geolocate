defmodule Bonfire.Geolocate.Integration do
  def is_admin(user) do
    if Map.get(user, :local_user) do
      Map.get(user.local_user, :is_instance_admin)
    else
      false # FIXME
    end
  end
end
