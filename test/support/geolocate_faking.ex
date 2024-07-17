# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Geolocate.Test.Faking do
  @moduledoc false

  import Grumble
  import Bonfire.API.GraphQL.Test.GraphQLFields
  import Bonfire.API.GraphQL.Test.GraphQLAssertions

  ## assertions

  def assert_geolocation(%Bonfire.Geolocate.Geolocation{} = geo) do
    assert_geolocation(Map.from_struct(geo))
  end

  def assert_geolocation(geo) do
    assert_object(geo, :assert_geolocation,
      id: &assert_ulid/1,
      name: &assert_binary/1,
      note: assert_optional(&assert_binary/1),
      lat: assert_optional(&assert_float/1),
      long: assert_optional(&assert_float/1)
    )
  end

  ## graphql queries

  def geolocation_query_fields(extra \\ []) do
    extra ++ ~w(id name mappable_address lat long alt note geom)a
  end

  def geolocation_mutation_fields(extra \\ []) do
    [
      spatial_thing: extra ++ ~w(id name mappable_address lat long alt note geom)a
    ]
  end

  def geolocation_query(options \\ []) do
    options = Keyword.put_new(options, :id_type, :id)
    gen_query(:id, &geolocation_subquery/1, options)
  end

  def geolocation_subquery(options \\ []) do
    gen_subquery(:id, :spatial_thing, &geolocation_query_fields/1, options)
  end

  def geolocation_pages_subquery(options \\ []) do
    args = [
      after: var(:after),
      before: var(:before),
      limit: var(:limit)
    ]

    page_subquery(
      :spatial_things_pages,
      &geolocation_query_fields/1,
      [{:args, args} | options]
    )
  end

  def geolocation_pages_query(options \\ []) do
    params =
      [
        after: list_type(:cursor),
        before: list_type(:cursor),
        limit: :int
      ] ++ Keyword.get(options, :params, [])

    gen_query(&geolocation_pages_subquery/1, [{:params, params} | options])
  end

  def create_geolocation_mutation(options \\ []) do
    gen_mutation(
      [spatial_thing: type!(:spatial_thing_create_params)],
      &create_geolocation_submutation/1,
      options
    )
  end


  def create_geolocation_submutation(options \\ []) do
    gen_submutation(
      [spatial_thing: var(:spatial_thing)],
      :create_spatial_thing,
      &geolocation_mutation_fields/1,
      options
    )
  end

  def update_geolocation_mutation(options \\ []) do
    gen_mutation(
      [spatial_thing: type!(:spatial_thing_update_params)],
      &update_geolocation_submutation/1,
      options
    )
  end

  def update_geolocation_submutation(options \\ []) do
    gen_submutation(
      [spatial_thing: var(:spatial_thing)],
      :update_spatial_thing,
      &geolocation_mutation_fields/1,
      options
    )
  end

  def delete_geolocation_mutation(options \\ []) do
    gen_mutation([id: type!(:id)], &delete_geolocation_submutation/1, options)
  end

  def delete_geolocation_submutation(_options \\ []) do
    field(:delete_spatial_thing, args: [id: var(:id)])
  end
end
