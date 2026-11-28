defmodule Rescord.Storage.Named do
  @moduledoc """
  The keys of the store that the records of a resource name, for the
  command that compares the store with the database
  (`Rescord.Storage.Compare`, ADR 0091).

  A record of a file holds the key of the file in `key`, and the key of
  its thumbnail in `thumbnail_key`. A domain that keeps files gives the
  keys of its records with one function, `file_keys/1`, and that function
  calls `keys/3` for each of its resources.

  `keys/3` reads the table itself, with no actor, no filter of the
  archive and no instant: each row counts, the row of a removed record
  and each old version of a temporal record too. Rescord deletes no row
  that names a file, so the rows hold each key that the history can name.
  It runs no action and changes nothing.
  """

  import Ecto.Query

  alias Rescord.{Repo, Storage}

  @typedoc """
  A key that a record names: the key, the kind of the record in words,
  such as `"photo"`, and the id of the record.
  """
  @type entry :: {Storage.key(), kind :: String.t(), id :: String.t()}

  @columns [:key, :thumbnail_key]

  @doc """
  Each key that a row of the table of `resource` names, in the schema of
  the organisation with the id `organisation_id`. `kind` is the word for
  a record of the resource in the report.
  """
  @spec keys(module, String.t(), String.t()) :: [entry]
  def keys(resource, kind, organisation_id)
      when is_atom(resource) and is_binary(kind) and is_binary(organisation_id) do
    table = AshPostgres.DataLayer.Info.table(resource)
    columns = Enum.filter(@columns, &Ash.Resource.Info.attribute(resource, &1))
    fields = [:id | columns]

    # A temporal record has a row for each version, with the same keys.
    from(row in table, distinct: true, select: map(row, ^fields))
    |> Repo.all(prefix: schema(organisation_id), timeout: :timer.minutes(5))
    |> Enum.flat_map(fn row ->
      id = Ecto.UUID.load!(row.id)
      for column <- columns, key = row[column], is_binary(key), do: {key, kind, id}
    end)
  end

  # The schema of an organisation (ADR 0011), as `Rescord.Repo.all_tenants/0`
  # names it.
  defp schema(organisation_id), do: "org_" <> organisation_id
end
