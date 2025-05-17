defmodule Bonfire.Geolocate.PlacePreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop activity, :any, default: nil
  prop object, :any, default: nil
  prop parent_id, :any, default: nil
end
