# SPDX-License-Identifier: AGPL-3.0-only

# if Application.compile_env(:bonfire_api_graphql, :modularity) == :disabled or
#      not Code.ensure_loaded?(Bonfire.API.GraphQL.Test.GraphQLFields) or
#      not Code.ensure_loaded?(Grumble) do
#   # the plain variant is also used when Grumble is not on the code path of this dependency's compile (it is not one of its declared deps), which otherwise fails the compile when the GraphQL test helpers were just compiled in the same run
# Grumble is not checked here: it is a dev/test dependency that is not on the code path when this compiles as a dependency, so the GraphQL variant calls it remotely through private wrappers (as `Bonfire.API.GraphQL.Test.GraphQLFields` does) instead of falling back to the plain variant
if Application.compile_env(:bonfire_api_graphql, :modularity) == :disabled or
     not Code.ensure_loaded?(Bonfire.API.GraphQL.Test.GraphQLFields) do
  defmodule Bonfire.Geolocate.Test.Faking do
    import ExUnit.Assertions

    def assert_geolocation(geo) do
      assert is_struct(geo)
      assert Map.has_key?(geo, :id)
      assert Map.has_key?(geo, :name)
      assert Map.has_key?(geo, :mappable_address)
      assert Map.has_key?(geo, :lat)
      assert Map.has_key?(geo, :long)
      assert Map.has_key?(geo, :note)
    end
  end
else
  defmodule Bonfire.Geolocate.Test.Faking do
    import Bonfire.Common.Extend
    @moduledoc false

    # import Grumble
    # `import` needs the module at compile time and a remote call doesn't
    defp field(name, set \\ []), do: Grumble.field(name, set)
    defp list_type(name, set \\ []), do: Grumble.list_type(name, set)
    defp type!(name, set \\ []), do: Grumble.type!(name, set)
    defp var(name), do: Grumble.var(name)

    import(Bonfire.API.GraphQL.Test.GraphQLFields)
    import(Bonfire.API.GraphQL.Test.GraphQLAssertions)

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
end
