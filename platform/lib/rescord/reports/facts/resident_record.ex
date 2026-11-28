defmodule Rescord.Reports.Facts.ResidentRecord do
  @moduledoc """
  The facts of the record of one resident: what its page shows, the part of
  its journal that the person asked for, and its photos on request.

  The photos are the thumbnails, `max_photos/0` at most, the newest first.
  The record names no member: it can leave the refuge.
  """

  @behaviour Rescord.Reports.Facts

  alias Rescord.{Journal, Photos, Residents}
  alias Rescord.Reports.Facts.Places

  @max_photos 24

  @doc "The most photos that a record holds."
  def max_photos, do: @max_photos

  @impl true
  def read(%{resident_id: id} = arguments, options, now) do
    with {:ok, resident} <- resident(id, options),
         {:ok, places} <- Places.read(options),
         {:ok, measurements} <- Journal.latest_measurements(id, options),
         {:ok, entries} <- entries(arguments[:journal], id, options),
         {:ok, files_of} <- Journal.attachments_of(Enum.map(entries, & &1.id), options),
         {:ok, profile} <- profile(id, options),
         {:ok, photos, more} <- photos(arguments[:photos], id, options) do
      files =
        Map.new(photos, &{&1.file, &1.bytes})
        |> then(&if(profile, do: Map.put(&1, profile.file, profile.bytes), else: &1))

      {:ok,
       %{
         resident: resident,
         today: Rescord.Accounts.local_date(options[:tenant], now),
         relations: Residents.relations(id, options),
         homes: Map.get(places.homes, id, []),
         measurements: measurements,
         journal: arguments[:journal],
         entries: Enum.map(entries, &%{entry: &1, files: length(Map.get(files_of, &1.id, []))}),
         profile: profile && profile.file,
         photos: Enum.map(photos, &Map.take(&1, [:file, :caption, :taken_on])),
         more_photos: more,
         files: files
       }}
    end
  end

  @doc "One resident with its facts, or the error that says that there is none."
  def resident(id, options) do
    case Residents.resident_with_facts(id, options) do
      {:ok, %{} = resident} ->
        {:ok, resident}

      {:ok, nil} ->
        {:error,
         Ash.Error.Query.NotFound.exception(resource: Residents.Resident, primary_key: id)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  The profile picture of a resident for a template: its path and the bytes
  of its thumbnail, or `nil` for a resident with none.
  """
  def profile(id, options) do
    with {:ok, %{} = photo} <- Photos.profile_photo(id, options),
         {:ok, _photo, bytes} <- Photos.photo_file(photo.id, :thumbnail, options) do
      {:ok, %{file: "photos/profile.webp", bytes: bytes}}
    else
      # No picture, or a picture whose file the store does not have.
      {:ok, nil} -> {:ok, nil}
      {:error, :not_found} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  defp entries(:none, _id, _options), do: {:ok, []}
  defp entries(:all, id, options), do: Journal.entries(id, options)
  defp entries(_medical, id, options), do: Journal.entries(id, [only: :medical] ++ options)

  defp photos(true, id, options) do
    with {:ok, items} <- Photos.photos_of(id, options) do
      photos =
        items
        |> Enum.take(@max_photos)
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {item, number} ->
          case thumbnail(item, options) do
            {:ok, bytes} ->
              [
                %{
                  file: "photos/#{number}.webp",
                  bytes: bytes,
                  caption: item.caption,
                  taken_on: item.taken_on
                }
              ]

            # A photo with no thumbnail in the store is not in the record.
            _no_file ->
              []
          end
        end)

      {:ok, photos, max(length(items) - @max_photos, 0)}
    end
  end

  defp photos(_no, _id, _options), do: {:ok, [], 0}

  defp thumbnail(%{photo: %{id: id}}, options) do
    with {:ok, _photo, bytes} <- Photos.photo_file(id, :thumbnail, options), do: {:ok, bytes}
  end

  defp thumbnail(%{attachment: %{id: id}}, options) do
    with {:ok, _attachment, bytes} <- Journal.attachment_thumbnail(id, options), do: {:ok, bytes}
  end
end
