defmodule Rescord.Health.Checks.Migrations do
  @moduledoc """
  C11 of issue 38: a migration that this version of Rescord has and the
  database has not run, while the server runs. `bin/migrate` runs each one
  before a start (ADR 0081), so one that waits is a fault: a schema of an
  organisation that a migration left behind, or an organisation that was
  made while the migrations ran. The count is the number of schemas
  behind, and the ids are those of their organisations.

  It reads the versions from the tables `schema_migrations` with SQL, and
  not with `Ecto.Migrator`, which would make the table in a schema that
  has none: a check writes nothing.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :migrations
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :hourly
  @impl true
  def title, do: "Migrations that the database has not run"

  @impl true
  def explain,
    do:
      "Some schemas are behind this version of Rescord: the database (no id) or the " <>
        "organisations of the ids. Run bin/migrate, which rehearses the migrations first, " <>
        "and read what it says."

  @impl true
  def run(_context) do
    repo = Rescord.Repo
    database = versions(Ecto.Migrator.migrations_path(repo))
    tenant = versions(Ecto.Migrator.migrations_path(repo, "tenant_migrations"))

    behind_database? = not MapSet.subset?(database, done("public"))

    %{rows: organisations} = repo.query!("select id from public.organisations order by id", [])

    behind =
      for [id] <- organisations,
          id = Ecto.UUID.load!(id),
          not MapSet.subset?(tenant, done("org_" <> id)),
          do: id

    count = length(behind) + if(behind_database?, do: 1, else: 0)
    if count == 0, do: ok(), else: %{level: :fail, count: count, ids: Enum.take(behind, 20)}
  end

  @doc "The versions of the migration files in `directory`."
  @spec versions(Path.t()) :: MapSet.t(integer)
  def versions(directory) do
    directory
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case Integer.parse(Path.basename(path)) do
        {version, "_" <> _rest} -> [version]
        _other -> []
      end
    end)
    |> MapSet.new()
  end

  defp done(schema) do
    %{rows: [[table?]]} =
      Rescord.Repo.query!(
        "select to_regclass(format('%I.schema_migrations', $1::text)) is not null",
        [schema]
      )

    if table? do
      %{rows: rows} =
        Rescord.Repo.query!(
          "select version from #{quote_schema(schema)}.schema_migrations",
          []
        )

      MapSet.new(rows, fn [version] -> version end)
    else
      MapSet.new()
    end
  end

  defp quote_schema(schema) do
    if String.match?(schema, ~r/\A[a-z0-9_-]+\z/),
      do: ~s("#{schema}"),
      else: raise(ArgumentError, "not the name of a schema")
  end
end
