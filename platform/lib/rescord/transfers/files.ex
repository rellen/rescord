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

  @doc """
  The key of each file that the copy of a transfer to the organisation
  names, as `Rescord.Storage.Named` gives the keys of a resource. A
  transfer keeps its files in each state: the refuge that receives it has
  them from the send or the import on. An export keeps no file on this
  server, and names no organisation that receives it.

  It reads the table itself, with no actor.
  """
  @spec keys_of(String.t()) :: [Storage.Named.entry()]
  def keys_of(organisation_id) when is_binary(organisation_id) do
    from(transfer in "transfers",
      where: transfer.to_organisation_id == type(^organisation_id, Ecto.UUID),
      select: {transfer.id, transfer.snapshot}
    )
    |> Repo.all(timeout: :timer.minutes(5))
    |> Enum.flat_map(fn {id, copy} ->
      transfer_id = Ecto.UUID.load!(id)

      # `key/3` raises for an id that can be no part of a key, and a file
      # with such an id was never put in the store.
      for %{"id" => file_id} <- Snapshot.files(copy || %{}),
          Storage.segment?(file_id),
          do: {key(organisation_id, transfer_id, file_id), "transfer", transfer_id}
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
