defmodule Rescord.Images.Workers.Complete do
  @moduledoc """
  The job that makes the files that a photo lacks (issue 34):

    * **A journal photo from before ADR 0055** (an image with no
      `thumbnail_key`, which Rescord 0.1.0 kept as it was sent, with its
      EXIF and its GPS position) goes through `Rescord.Images.prepare/1`.
      The clean photo goes under the same key, and gets its thumbnail and
      its display file. Each copy of it in a transfer to an organisation of
      this server gets the clean bytes too, and its size in the copy.
    * **A photo with no display file** (not a GIF) gets one, with
      `Rescord.Images.display/1`.

  The rows get the new keys and the new size with an update of the table:
  each version row of a photo, since the keys and the size are facts of
  the file and each version names the same files, with no new version and
  no entry in the paper trail. A photo record that names a journal photo
  (`adopt`) gets the keys of its attachment.

  Oban starts it each hour (`config/config.exs`) with no arguments, and that
  run puts one job for each organisation. A job of an organisation takes
  `batch/0` rows of the attachments, then of the photo records, in the
  order of their ids, and puts the job of the next batch, so the queue
  `images` is free between two batches. A photo goes through the slots of
  `Rescord.Images.Limit` with the uploads of people; a photo that waits too
  long ends the batch, and the job snoozes for a minute.

  A photo that it cannot make (unreadable, or with no file in the store)
  stays as it is. The batch goes past it, the next hourly start tries it
  again, and a warning of each batch gives the count. It reads and writes
  with no actor, as `Rescord.Storage.Named` reads. A fault after a put of a
  new key leaves a file that no record names, which `bin/check-files`
  reports as a leftover, as for an upload.
  """

  use Boundary, top_level?: true, deps: [Rescord, Rescord.Transfers]

  use Oban.Worker,
    queue: :images,
    max_attempts: 20,
    unique: [
      period: :infinity,
      keys: [:organisation_id],
      states: [:available, :scheduled, :retryable]
    ]

  import Ecto.Query

  require Logger

  alias Rescord.{Images, Repo, Storage}
  alias Rescord.Storage.Errors.RefusedFile
  alias Rescord.Storage.Upload

  @batch 50
  @kinds ["attachments", "photos"]

  @doc "The rows of one job."
  def batch, do: @batch

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organisation_id" => organisation_id} = args}) do
    kind = Map.get(args, "kind", "attachments")
    rows = rows(kind, organisation_id, args["after"])

    case complete_each(rows, kind, organisation_id) do
      :busy ->
        {:snooze, 60}

      {:ok, skipped} ->
        if skipped > 0 do
          Logger.warning(
            "Photos that Rescord could not complete in the organisation #{organisation_id}: " <>
              "#{skipped}. The job tries them again at its next hourly start."
          )
        end

        next(kind, organisation_id, rows)
    end
  end

  def perform(%Oban.Job{}) do
    for "org_" <> organisation_id <- Repo.all_tenants() do
      {:ok, _job} = Oban.insert(new(%{"organisation_id" => organisation_id}))
    end

    :ok
  end

  @doc """
  How many journal photos of the organisation still carry the metadata that
  they were sent with: images with no thumbnail, from Rescord 0.1.0.
  `bin/check-files` prints the sum.
  """
  @spec uncleaned(String.t()) :: non_neg_integer
  def uncleaned(organisation_id) do
    from(attachment in "journal_attachments",
      where: like(attachment.content_type, "image/%") and is_nil(attachment.thumbnail_key),
      select: count()
    )
    |> Repo.one(prefix: schema(organisation_id))
  end

  # The next batch of the same kind, or the first of the next kind.
  defp next(kind, organisation_id, rows) do
    args =
      cond do
        length(rows) == @batch ->
          %{"organisation_id" => organisation_id, "kind" => kind, "after" => List.last(rows).id}

        kind == "attachments" ->
          %{"organisation_id" => organisation_id, "kind" => "photos"}

        true ->
          nil
      end

    if args, do: {:ok, _job} = Oban.insert(new(args))
    :ok
  end

  defp rows(kind, organisation_id, after_id) when kind in @kinds do
    kind
    |> query()
    |> after_id(after_id)
    |> order_by([row], row.id)
    |> limit(@batch)
    |> Repo.all(prefix: schema(organisation_id))
    |> Enum.map(&%{&1 | id: Ecto.UUID.load!(&1.id)})
  end

  # A journal photo with no thumbnail, or with no display file.
  defp query("attachments") do
    from(attachment in "journal_attachments",
      where:
        like(attachment.content_type, "image/%") and
          (is_nil(attachment.thumbnail_key) or
             (is_nil(attachment.display_key) and attachment.content_type != "image/gif")),
      select: %{id: attachment.id, key: attachment.key, thumbnail_key: attachment.thumbnail_key}
    )
  end

  # A photo record with no display file, one row for its versions. A photo
  # of the journal gets the keys of its attachment, so it is not here.
  defp query("photos") do
    from(photo in "photos",
      where:
        is_nil(photo.attachment_id) and is_nil(photo.display_key) and
          like(photo.content_type, "image/%") and photo.content_type != "image/gif",
      distinct: true,
      select: %{id: photo.id, key: photo.key, thumbnail_key: photo.thumbnail_key}
    )
  end

  defp after_id(query, nil), do: query
  defp after_id(query, id), do: where(query, [row], row.id > type(^id, Ecto.UUID))

  # `:busy` at the first photo that waited too long, or the count of the
  # photos that it could not make.
  defp complete_each(rows, kind, organisation_id) do
    Enum.reduce_while(rows, {:ok, 0}, fn row, {:ok, skipped} ->
      case complete(row, kind, organisation_id) do
        :ok -> {:cont, {:ok, skipped}}
        :busy -> {:halt, :busy}
        :skipped -> {:cont, {:ok, skipped + 1}}
      end
    end)
  end

  # A journal photo of Rescord 0.1.0: clean it, and its copies.
  defp complete(%{thumbnail_key: nil} = row, "attachments", organisation_id) do
    with {:ok, bytes} <- Storage.get(row.key),
         {:ok, files} <- Images.prepare(bytes) do
      thumbnail_key = Storage.key(organisation_id, ["thumbnails", row.id])
      display_key = files.display && Storage.key(organisation_id, ["displays", row.id])

      with :ok <- Upload.put(row.key, thumbnail_key, files, display_key),
           :ok <- clean_copies(organisation_id, row.id, files.bytes) do
        set = [
          size: byte_size(files.bytes),
          thumbnail_key: thumbnail_key,
          display_key: display_key
        ]

        write_attachment(organisation_id, row.id, set)
      end
    end
    |> outcome()
  end

  defp complete(row, kind, organisation_id) do
    display_key = Storage.key(organisation_id, ["displays", row.id])

    with {:ok, bytes} <- Storage.get(row.key),
         {:ok, display} when is_binary(display) <- Images.display(bytes),
         :ok <- Storage.put(display_key, display, "image/webp") do
      case kind do
        "attachments" -> write_attachment(organisation_id, row.id, display_key: display_key)
        "photos" -> write_photo(organisation_id, row.id, display_key: display_key)
      end
    end
    |> outcome()
  end

  defp outcome(:ok), do: :ok
  defp outcome({:error, %RefusedFile{reason: :busy}}), do: :busy
  defp outcome(_other), do: :skipped

  # The attachment, and each version of each photo record that names it.
  defp write_attachment(organisation_id, id, set) do
    prefix = schema(organisation_id)

    {:ok, _} =
      Repo.transaction(fn ->
        from(attachment in "journal_attachments", where: attachment.id == type(^id, Ecto.UUID))
        |> Repo.update_all([set: set], prefix: prefix)

        from(photo in "photos", where: photo.attachment_id == type(^id, Ecto.UUID))
        |> Repo.update_all([set: set], prefix: prefix)
      end)

    :ok
  end

  defp write_photo(organisation_id, id, set) do
    from(photo in "photos", where: photo.id == type(^id, Ecto.UUID))
    |> Repo.update_all([set: set], prefix: schema(organisation_id))

    :ok
  end

  # Each copy that the store has gets the clean bytes, and its size in the
  # copy. A copy that the job of its transfer has not made yet is left: it
  # reads the clean file when it comes to it.
  defp clean_copies(organisation_id, file_id, bytes) do
    organisation_id
    |> Rescord.Transfers.file_copies(file_id)
    |> Enum.reduce_while(:ok, fn {transfer_id, key}, :ok ->
      with {:ok, _old} <- Storage.get(key),
           :ok <- Storage.put(key, bytes, Images.type_of(bytes)) do
        :ok = Rescord.Transfers.put_file_size(transfer_id, file_id, byte_size(bytes))
        {:cont, :ok}
      else
        {:error, :not_found} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp schema(organisation_id), do: "org_" <> organisation_id
end
