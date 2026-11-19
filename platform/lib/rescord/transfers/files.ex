defmodule Rescord.Transfers.Files do
  @moduledoc """
  The photos and PDFs of a copy (ADR 0043). The refuge that receives a
  transfer keeps its own copy of each file, under
  `<receiving refuge>/transfers/<transfer>/<file>` in the store
  (`Rescord.Storage`), so the copy keeps its files when the first refuge
  removes one, and on another server.
  """

  alias Rescord.Storage

  @doc "The key of a file of a transfer, in the store of the refuge that receives it."
  @spec key(String.t(), String.t(), String.t()) :: Storage.key()
  def key(to_organisation_id, transfer_id, file_id),
    do: Storage.key(to_organisation_id, ["transfers", transfer_id, file_id])

  @doc """
  The bytes of each source of `Rescord.Transfers.Snapshot.build/3`, as
  `{id, bytes}`.
  """
  @spec read([map]) :: {:ok, [{String.t(), binary}]} | {:error, term}
  def read(sources) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, read} ->
      case Storage.get(source["key"]) do
        {:ok, bytes} -> {:cont, {:ok, [{source["id"], bytes} | read]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

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

  @doc "A file that the copy of a transfer names, or `nil`."
  @spec named(map, String.t()) :: map | nil
  def named(snapshot, file_id) do
    snapshot
    |> Rescord.Transfers.Archive.entries()
    |> Enum.flat_map(&(&1["files"] || []))
    |> Enum.find(&(&1["id"] == file_id))
  end
end
