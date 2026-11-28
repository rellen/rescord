defmodule Rescord.Health.Checks.FileKeys do
  @moduledoc """
  C14 of issue 38: a record of a file whose key names another
  organisation. Each key starts with the id of the organisation of its
  record (`Rescord.Storage.key/2`), and `bin/check-files` and the store
  read it so: a key of another organisation shows a file of that
  organisation, or counts as a leftover there.

  It reads the photos, the journal attachments and the receipts, with each
  version of a photo. The ids are those of the records.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :file_keys
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Files under the key of another organisation"

  @impl true
  def explain,
    do:
      "A record names a file whose key does not start with its own organisation, so it could " <>
        "show a file of another one. No action of Rescord writes such a key: report it, with " <>
        "the ids."

  @impl true
  def run(%{organisation: organisation} = context) do
    tables = [
      {"photos", ~w(key thumbnail_key display_key)},
      {"journal_attachments", ~w(key thumbnail_key display_key)},
      {"expense_receipts", ~w(key thumbnail_key)}
    ]

    sql =
      Enum.map_join(tables, "\nunion\n", fn {name, columns} ->
        wrong =
          Enum.map_join(columns, " or ", &"(r.#{&1} is not null and left(r.#{&1}, $2) <> $1)")

        "select r.id from #{table(context, name)} r where #{wrong}"
      end)

    prefix = organisation.id <> "/"

    sql
    |> query([prefix, String.length(prefix)])
    |> found(:fail)
  end
end
