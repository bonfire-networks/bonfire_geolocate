if Code.ensure_loaded?(SweetXml) and Code.ensure_loaded?(Explorer) do
  defmodule Bonfire.Geolocate.FoursquarePlaces do
    @moduledoc """
    Downloads location data files from https://docs.foursquare.com/data-products/docs/access-fsq-os-places

    # TODO: import places into MeiliSearch using `_geo` field (to enable searching for places with geo radius or bounding box), and dump the Meili index so it can be imported by other instances without having to run this script.
    """

    import Untangle
    import SweetXml
    alias Explorer.DataFrame

    # TODO: read from config
    @dl_dir "data/geolocate/4square_places"
    @meili_index "geolocations"
    @max_concurrency 3
    @timeout 600_000
    @base_url "https://fsq-os-places-us-east-1.s3.amazonaws.com"
    @target_prefixes [
      "release/dt=2024-12-03/places/parquet",
      "release/dt=2024-12-03/categories/parquet"
    ]
    # Customize based on your memory and processing power
    @chunk_size 1000

    def search(q) do
      Bonfire.Search.search(q, index: @meili_index)
    end

    def index_name(n \\ @meili_index) do
      Bonfire.Search.Indexer.index_name(n)
    end

    def list_files do
      # Ensure downloads directory exists
      File.mkdir_p!(@dl_dir)

      # Get list of files from S3
      {:ok, %{status: 200, body: body}} = Req.get(@base_url)

      # ns = "http://s3.amazonaws.com/doc/2006-03-01/"

      body
      # |> IO.inspect(label: "XML Document")
      |> xpath(
        ~x"//Contents/Key/text()"l
        #   xmlns: ns
      )
      # |> IO.inspect(label: "XPath Results")
      |> Enum.map(&to_string/1)
      |> filter_remote_files()
    end

    def download_files do
      # Get list of files to download
      list_files()
      |> Task.async_stream(&download_file(&1),
        max_concurrency: @max_concurrency,
        timeout: @timeout
      )
      |> Enum.each(fn
        {:ok, result} ->
          {:ok, result}

        {:error, reason} ->
          IO.puts("Error downloading file: #{reason}")
          {:error, reason}
      end)
    end

    def download_files_slow do
      # Download each file
      Enum.each(list_files(), &download_file/1)
    end

    defp download_file(file_path) do
      url = "#{@base_url}/#{file_path}"
      filename = Path.basename(file_path)
      local_path = Path.join(@dl_dir, filename)

      IO.puts("Downloading #{filename}...")

      # Using Req to download the file
      case Req.get!(url, into: File.stream!(local_path)) do
        %{status: 200} ->
          {:ok, filename}

        response ->
          {:error, "Failed to download #{filename}: #{inspect(response)}"}
      end
    end

    defp filter_remote_files(files) do
      Enum.filter(files, fn file ->
        Enum.any?(@target_prefixes, &String.starts_with?(file, &1)) and
          String.ends_with?(file, ".parquet")
      end)
    end

    def import_downloaded_places_and_dump do
      with {:ok, _} <- clean_indexes(),
           {:ok, _} <- setup_places_index() do
        # TODO: support getting directly from remote s3 parquet without pre-downloading: Enum.map( list_files(), &DataFrame.from_parquet/1)

        # Get all downloaded place files
        place_files =
          File.ls!(@dl_dir)
          |> Enum.filter(&String.contains?(&1, "places"))

        # Import all place files
        results =
          Enum.map(place_files, fn file ->
            IO.puts("Importing #{file}...")
            import_places_to_meili(Path.join(@dl_dir, file))
          end)

        # Create dump after successful import
        case Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end) do
          true ->
            IO.puts("All imports successful. Creating dump...")
            create_meili_dump()

          false ->
            IO.puts("Some imports failed. Skipping dump creation.")
            {:error, :import_failed}
        end
      end
    end

    defp import_places_to_meili(filename) do
      client = Bonfire.Search.MeiliLib.get_client()

      case DataFrame.from_parquet(filename) do
        {:ok, df} ->
          places =
            df
            |> DataFrame.to_rows()
            |> Stream.chunk_every(@chunk_size)
            |> Stream.map(fn chunk ->
              chunk
              |> Enum.reject(fn place -> not is_nil(place["date_closed"]) end)
              |> Enum.map(&prepare_place_for_meili/1)
              |> then(fn prepared_places ->
                case Meilisearch.Document.create_or_replace(client, index_name(), prepared_places) do
                  {:ok, task} ->
                    IO.puts("Imported batch successfully. Task ID: #{task.taskUid}")
                    {:ok, length(prepared_places)}

                  {:error, error} ->
                    IO.warn("Failed to import batch: #{inspect(error)}")
                    {:error, error}
                end
              end)
            end)
            |> Enum.reduce({0, 0}, fn
              {:ok, count}, {success, failures} -> {success + count, failures}
              {:error, _}, {success, failures} -> {success, failures + 1}
            end)

          IO.puts(
            "Import complete. Successfully imported #{elem(places, 0)} places with #{elem(places, 1)} failed batches."
          )

          {:ok, places}

        {:error, reason} ->
          {:error, reason}
      end
    end

    def prepare_place_for_meili(place) do
      debug(place)
      # Transform the place data to include all available fields
      %{
        # Core identifiers and name
        id: place["fsq_place_id"],
        name: place["name"],
        #   foursquare_url: "http://www.foursquare.com/v/#{place["fsq_place_id"]}",

        # Location data
        address: place["address"],
        postcode: place["postcode"],
        locality: place["locality"],
        region: place["region"],
        admin_region: place["admin_region"],
        post_town: place["post_town"],
        po_box: place["po_box"],
        # ISO country code TODO: add field with full name
        country: place["country"],

        # Geolocation data
        _geo:
          case {place["latitude"], place["longitude"]} do
            {latitude, longitude} when not is_nil(latitude) and not is_nil(longitude) ->
              %{
                lat: latitude,
                lng: longitude
              }

            _ ->
              nil
          end,

        # If bbox is present, include it
        bbox:
          case place["bbox"] do
            %{"xmin" => xmin} = bbox when not is_nil(xmin) ->
              %{
                xmin: xmin,
                ymin: bbox["ymin"],
                xmax: bbox["xmax"],
                ymax: bbox["ymax"]
              }

            _ ->
              nil
          end,

        # Categories
        #   category_ids: place["fsq_category_ids"],
        categories: place["fsq_category_labels"],

        # Contact information
        telephone: place["tel"],
        website: place["website"],
        email: place["email"],

        # Social media
        facebook: place["facebook_id"],
        instagram: place["instagram"],
        twitter: place["twitter"],

        # Dates
        #   created_at: place["date_created"],
        refreshed_at: place["date_refreshed"]
        #   closed_at: place["date_closed"],

        # Additional metadata
        #   is_closed: not is_nil(place["date_closed"]),
        #   last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      }
      |> remove_nil_values()
      |> debug()
    end

    # Helper function to remove nil values from the map
    defp remove_nil_values(map) do
      map
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end

    defp clean_indexes do
      client = Bonfire.Search.MeiliLib.get_client()

      with {:ok, %{results: indexes}} <- Meilisearch.Index.list(client) |> debug() do
        indexes
        |> Enum.reject(fn index -> index.uid == index_name() end)
        |> case do
          [] ->
            IO.puts("No irrelevant indexes found.")
            {:ok, :clean}

          indexes_to_delete ->
            IO.puts("\nFound #{length(indexes_to_delete)} indexes that should be deleted:")

            indexes_to_delete
            |> Enum.each(fn index ->
              IO.puts("- #{index.uid} (created at #{index.createdAt})")
            end)

            case IO.gets("\nDo you want to delete these indexes? [y/N]: ") do
              input when input in ["y\n", "Y\n"] ->
                results =
                  Enum.map(indexes_to_delete, fn index ->
                    case Meilisearch.Index.delete(client, index.uid) do
                      {:ok, task} ->
                        IO.puts("Deleted index #{index.uid}. Task ID: #{task.taskUid}")
                        {:ok, index.uid}

                      {:error, error} ->
                        IO.warn("Failed to delete index #{index.uid}: #{inspect(error)}")
                        {:error, {index.uid, error}}
                    end
                  end)

                case Enum.split_with(results, fn
                       {:ok, _} -> true
                       {:error, _} -> false
                     end) do
                  {successes, []} ->
                    IO.puts("\nSuccessfully deleted #{length(successes)} indexes.")
                    {:ok, :cleaned}

                  {successes, failures} ->
                    IO.puts("\nDeleted #{length(successes)} indexes.")
                    IO.puts("Failed to delete #{length(failures)} indexes.")
                    {:error, :partial_failure}
                end

              _ ->
                IO.puts("Deletion cancelled.")
                {:ok, :cancelled}
            end
        end
      else
        {:error, error} ->
          IO.warn("Failed to list indexes: #{inspect(error)}")
          {:error, error}
      end
    end

    defp setup_places_index do
      client = Bonfire.Search.MeiliLib.get_client()

      # Check if index exists
      case Meilisearch.Index.get(client, index_name()) do
        {:ok, _index} ->
          IO.puts("Places index already exists.")
          {:ok, :exists}

        _ ->
          # Create new index with proper configuration
          case Meilisearch.Index.create(client, %{
                 uid: index_name(),
                 primaryKey: "id"
               }) do
            {:ok, task} ->
              IO.puts("Created places index. Task ID: #{task.taskUid}")

              Meilisearch.Settings.FilterableAttributes.update(client, index_name(), [
                "_geo",
                "categories"
              ])

              Meilisearch.Settings.SearchableAttributes.update(client, index_name(), [
                "address",
                "name",
                "locality",
                "postcode",
                "country"
              ])

              {:ok, :created}

            {:error, error} ->
              IO.warn("Failed to create places index: #{inspect(error)}")
              {:error, error}
          end
      end
    end

    def create_meili_dump do
      client = Bonfire.Search.MeiliLib.get_client()

      case Meilisearch.Dump.create(client) do
        {:ok, task} ->
          IO.puts("Dump creation started. Task ID: #{task.taskUid}")
          {:ok, task}

        {:error, error} ->
          IO.warn("Failed to create dump: #{inspect(error)}")
          {:error, error}
      end
    end
  end
end
