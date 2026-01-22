defimpl Jason.Encoder, for: Geo.Point do
  def encode(struct, opts), do: Geo.JSON.encode!(struct) |> Jason.Encode.map(opts)
end
