defmodule Rescord.Transfers.Files do
  @moduledoc """
  The photos and PDFs of a copy (ADR 0043 and ADR 0057). The refuge that
  receives a transfer keeps its own copy of each file, under
  `<receiving refuge>/transfers/<transfer>/<file>` in the store
  (`Rescord.Storage`), so the copy keeps its files when the first refuge
  removes one, and on another server.
  """

  import Ecto.Query, only: [from: 2]

  alias Rescord.{Repo, Storage}
  alias Rescord.Transfers.Snapshot

  @doc "The key of a file of a transfer, in the store of the refuge that receives it."
  @spec key(String.t(), String.t(), String.t()) :: Storage.key()
  def key(to_organisation_id, transfer_id, file_id),
    do: Storage.key(to_organisation_id, ["transfers", transfer_id, file_id])

  @doc """
  The bytes of each source of `Rescord.Transfers.Snapshot.build/3`, as
  `{id, bytes}`.
  """
  @spec read([map]) :: {:ok, [{String.t(), binary}]} | {:error, :not_found | term}
  def read(sources) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, read} ->
      case bytes_of(source) do
        {:ok, bytes} -> {:cont, {:ok, [{source["id"], bytes} | read]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc """
  Copies one source of `Rescord.Transfers.Snapshot.build/3` to the store
  of the transfer: it reads the file by its key in the store of the refuge
  that sent it, and puts it under the key of the transfer
  (ADR 0100). A file is in memory while it is copied, and the job of a
  transfer copies one at a time. A put is safe to repeat: the same key
  gets the same bytes.

  `{:error, :not_found}` says that the store of the refuge that sent it
  does not have the file.
  """
  @spec copy_one(map, String.t(), String.t()) :: :ok | {:error, :not_found | term}
  def copy_one(source, to_organisation_id, transfer_id) do
    with {:ok, bytes} <- bytes_of(source) do
      store([{source["id"], bytes}], to_organisation_id, transfer_id)
    end
  end

  defp bytes_of(%{"key" => key}), do: Storage.get(key)

  @doc "Puts each file, as `{id, bytes}`, in the store of the transfer."
  @spec store([{String.t(), binary}], String.t(), String.t()) :: :ok | {:error, term}
  def store(files, to_organisation_id, transfer_id) do
    Enum.reduce_while(files, :ok, fn {id, bytes}, :ok ->
      type = Rescord.Journal.file_type(bytes) || "application/octet-stream"

      case Storage.put(key(to_organisation_id, transfer_id, id), bytes, type) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc """
  The key of each file that the copy of a transfer to the organisation
  names and that are in the store, as `Rescord.Storage.Named` gives the
  keys of a resource. A transfer keeps its files in each state. While it
  is `sending`, or after it `failed`, only the files that the job copied
  are named. An export keeps no file on this
  server, and names no organisation that receives it.

  It reads the table itself, with no actor.
  """
  @spec keys_of(String.t()) :: [Storage.Named.entry()]
  def keys_of(organisation_id) when is_binary(organisation_id) do
    from(transfer in "transfers",
      where: transfer.to_organisation_id == type(^organisation_id, Ecto.UUID),
      select: {transfer.id, transfer.snapshot, transfer.sources, transfer.files_copied}
    )
    |> Repo.all(timeout: :timer.minutes(5))
    |> Enum.flat_map(fn {id, copy, sources, copied} ->
      transfer_id = Ecto.UUID.load!(id)

      # `key/3` raises for an id that can be no part of a key, and a file
      # with such an id was never put in the store.
      for file_id <- in_store(copy, sources, copied),
          Storage.segment?(file_id),
          do: {key(organisation_id, transfer_id, file_id), "transfer", transfer_id}
    end)
  end

  # The ids of the files of a transfer that are in the store. While the job
  # copies them, and after it stopped, the first `copied` of the sources
  # are (ADR 0100); the rest are not yet, and are no missing file. After
  # the job delivered, and for a transfer before ADR 0100 or an import,
  # each file of the copy is.
  defp in_store(_copy, [_ | _] = sources, copied) when is_integer(copied),
    do: sources |> Enum.take(copied) |> Enum.map(& &1["id"]) |> Enum.filter(&is_binary/1)

  defp in_store(copy, _no_sources, _copied),
    do: for(%{"id" => file_id} <- Snapshot.files(copy || %{}), do: file_id)

  @doc "A file that the copy of a transfer names, or `nil`."
  @spec named(map, String.t()) :: map | nil
  def named(snapshot, file_id) do
    snapshot
    |> Snapshot.files()
    |> Enum.find(&(&1["id"] == file_id))
  end
end
