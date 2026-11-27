defmodule Rescord.Transfers.Files do
  @moduledoc """
  The photos and PDFs of a copy (ADR 0043 and ADR 0057). The refuge that
  receives a transfer keeps its own copy of each file, under
  `<receiving refuge>/transfers/<transfer>/<file>` in the store
  (`Rescord.Storage`), so the copy keeps its files when the first refuge
  removes one, and on another server.
  """

  alias Rescord.Storage
  alias Rescord.Transfers.Snapshot

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
      case bytes_of(source) do
        {:ok, bytes} -> {:cont, {:ok, [{source["id"], bytes} | read]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc """
  Copies each source of `Rescord.Transfers.Snapshot.build/3` to the store
  of the transfer, one file at a time, so a copy with many photos holds
  one of them in memory.
  """
  @spec copy([map], String.t(), String.t()) :: :ok | {:error, term}
  def copy(sources, to_organisation_id, transfer_id) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      with {:ok, bytes} <- bytes_of(source),
           :ok <- store([{source["id"], bytes}], to_organisation_id, transfer_id) do
        {:cont, :ok}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # A source holds its bytes, as that of a thumbnail does, or its key.
  defp bytes_of(%{"bytes" => bytes}) when is_binary(bytes), do: {:ok, bytes}
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

  @doc "A file that the copy of a transfer names, or `nil`."
  @spec named(map, String.t()) :: map | nil
  def named(snapshot, file_id) do
    snapshot
    |> Snapshot.files()
    |> Enum.find(&(&1["id"] == file_id))
  end
end
