defmodule Rescord.Health.Check do
  @moduledoc """
  A check of `Rescord.Health` (ADR 0114): a module that reads the database,
  or asks the server, and says whether something has drifted.

  - `name/0`: an atom of `Rescord.Health.Checks.names/0`. A metric tag and
    the row of the result use it.
  - `scope/0`: `:server` runs once, `:organisation` runs once for each
    organisation, with the schema of the organisation as `prefix`.
  - `cadence/0`: how often it runs: `:hourly`, `:daily` or `:weekly`.
  - `title/0`: what it looks for, in a few words, for `/root/health`.
  - `explain/0`: what a fault means, and what to do about it.
  - `run/1`: a level, a count, and at most 20 ids of what it found.

  `Rescord.Health` runs `run/1` inside a transaction that PostgreSQL holds
  read-only, with a time limit for each statement, and rolls it back. A
  check writes nothing to the store and sends nothing a person reads. Its
  finding holds counts and ids, never a value of a row (ADR 0077).

  `use Rescord.Health.Check` gives `query/3`, which counts the rows of a
  query that returns an `id` column and keeps the first 20 ids, and
  `table/2`, which names a table of the schema of the context.
  """

  @typedoc "What a check gets: the time of the run, and the organisation of an organisation check."
  @type context :: %{
          required(:now) => DateTime.t(),
          required(:organisation) => map | nil,
          required(:prefix) => String.t() | nil
        }

  @typedoc "What a check found."
  @type finding :: %{
          required(:level) => :ok | :note | :fail,
          required(:count) => non_neg_integer,
          required(:ids) => [Ecto.UUID.t()]
        }

  @callback name() :: atom
  @callback scope() :: :server | :organisation
  @callback cadence() :: :hourly | :daily | :weekly
  @callback title() :: String.t()
  @callback explain() :: String.t()
  @callback run(context) :: finding

  @doc """
  The time limit of one statement of the check, in milliseconds. 10 seconds
  unless the check says more.
  """
  @callback timeout() :: pos_integer

  @optional_callbacks timeout: 0

  @ids 20

  defmacro __using__(_opts) do
    quote do
      @behaviour Rescord.Health.Check
      import Rescord.Health.Check, only: [query: 1, query: 2, query: 3, table: 2, found: 2, ok: 0]
    end
  end

  @doc "A finding with nothing found."
  @spec ok() :: finding
  def ok, do: %{level: :ok, count: 0, ids: []}

  @doc """
  The finding of `{count, ids}` from `query/3`: `level` when the count is
  more than 0, else `:ok`.
  """
  @spec found({non_neg_integer, [Ecto.UUID.t()]}, :note | :fail) :: finding
  def found({0, _ids}, _level), do: ok()
  def found({count, ids}, level), do: %{level: level, count: count, ids: ids}

  @doc """
  Runs `sql`, a query whose rows have an `id` column of type uuid, and
  gives the number of its rows and the first 20 ids.
  """
  @spec query(String.t(), list, keyword) :: {non_neg_integer, [Ecto.UUID.t()]}
  def query(sql, params \\ [], opts \\ []) do
    wrapped = """
    select found.id, count(*) over () from (#{sql}) as found order by found.id limit #{@ids}
    """

    case Rescord.Repo.query!(wrapped, params, opts) do
      %{rows: []} ->
        {0, []}

      %{rows: [[_id, count] | _rest] = rows} ->
        {count, Enum.map(rows, fn [id, _count] -> Ecto.UUID.load!(id) end)}
    end
  end

  @doc ~S"""
  The quoted name of `name`, a table in the schema of the context: in the
  schema of the organisation, or in `public` for the server.

      table(context, "routines")  #=> ~s("org_…"."routines")
  """
  @spec table(context, String.t()) :: String.t()
  def table(%{prefix: nil}, name), do: ~s("public".) <> quote_name(name)
  def table(%{prefix: prefix}, name), do: quote_name(prefix) <> "." <> quote_name(name)

  defp quote_name(name) do
    if String.match?(name, ~r/\A[a-z0-9_-]+\z/),
      do: ~s("#{name}"),
      else: raise(ArgumentError, "not the name of a table or a schema")
  end
end
