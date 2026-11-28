defmodule Rescord.Health.Checks.StoreFiles do
  @moduledoc """
  C13 and C15 of issue 38: the store of the files against the database,
  each week, as `bin/check-files` compares them (ADR 0091,
  `Rescord.Storage.Compare`).

    * A fault: a file that a record names and the store does not have, or
      a file whose size in the store is not the size that its record keeps
      (photos, journal attachments and receipts keep the size of `key`).
    * A note: leftovers, files under the key of an organisation that no
      record names.

  The store is listed first, and then the records are read, so the file
  of an upload that ends in between is not missing: the store is asked
  for each file that the list does not have, as the command does. A
  leftover can be the file of an upload whose record was not there yet:
  it counts only when a second read of the records, after the first,
  still names no such file. A size that differs is asked of the store
  again, since the job of the images writes a clean photo and then its
  size.

  The run lists the whole store and reads each key, so it has a job of its
  own (`Rescord.Health.Workers.Check`) and a limit of 15 minutes for one
  statement. The ids are those of the records with a fault.
  """

  use Rescord.Health.Check

  alias Rescord.{Repo, Storage}
  alias Rescord.Storage.Compare

  # The domains that keep files, as `Rescord.Release.Files.domains/0` names
  # them: a test holds the two lists together.
  @domains [Rescord.Journal, Rescord.Photos, Rescord.Expenses, Rescord.Transfers, Rescord.Privacy]

  @sized ["photos", "journal_attachments", "expense_receipts"]

  @doc "The domains whose `file_keys/1` the check reads."
  @spec domains() :: [module]
  def domains, do: @domains

  @impl true
  def name, do: :store_files
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :weekly
  @impl true
  def timeout, do: :timer.minutes(15)
  @impl true
  def own_job?, do: true
  @impl true
  def title, do: "Files that are missing, or that differ from their record"

  @impl true
  def explain,
    do:
      "A fault: a record names a file that the store does not have, or a file whose size is " <>
        "not the size of its record. Run bin/check-files for the keys, and restore those " <>
        "files from a backup of the store. A note: files that no record names; " <>
        "bin/check-files lists them."

  @impl true
  def run(_context) do
    store = Storage.store()
    {:ok, files} = store.files()
    report = files |> Compare.run(named()) |> Compare.confirm(&store.get/1)

    missing = for {_key, _org, records, _reason} <- report.missing, {_kind, id} <- records, do: id
    differ = differ(files, store)

    case Enum.uniq(missing ++ differ) do
      [] ->
        named_now = named() |> Map.values() |> List.flatten() |> MapSet.new(&elem(&1, 0))
        leftovers = Enum.count(report.leftover, fn {key, _size} -> key not in named_now end)
        if leftovers == 0, do: ok(), else: %{level: :note, count: leftovers, ids: []}

      ids ->
        %{level: :fail, count: length(ids), ids: ids |> Enum.sort() |> Enum.take(20)}
    end
  end

  defp named do
    for "org_" <> organisation_id <- Repo.all_tenants(), into: %{} do
      {organisation_id, Enum.flat_map(@domains, & &1.file_keys(organisation_id))}
    end
  end

  # The ids of the records whose size is not the size of their file in the
  # list, and not in a second read of the file either.
  defp differ(files, store) do
    sizes = Map.new(files)

    for prefix <- Repo.all_tenants(),
        table <- @sized,
        [id, key, size] <- rows(prefix, table),
        listed <- [sizes[key]],
        listed != nil and listed != size,
        not same_now?(store, key, size),
        uniq: true,
        do: Ecto.UUID.load!(id)
  end

  defp rows(prefix, name) do
    Repo.query!(
      "select distinct id, key, size from #{table(%{prefix: prefix}, name)} where key is not null",
      [],
      timeout: :timer.minutes(5)
    ).rows
  end

  defp same_now?(store, key, size) do
    case store.get(key) do
      {:ok, bytes} -> byte_size(bytes) == size
      {:error, _reason} -> false
    end
  end
end
