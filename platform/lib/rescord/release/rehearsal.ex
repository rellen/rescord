defmodule Rescord.Release.Rehearsal do
  @moduledoc """
  The rehearsal of an upgrade (ADR 0081). Before a start changes anything,
  `run/1` runs each migration that has not run, of the database and of
  each organisation, in one transaction on one connection, and takes all
  of it back. A migration that fails on the rows of a rescue then fails
  here, and the database is as it was: the old version still runs on it.

  The connection is the one of `Ecto.Adapters.SQL.Sandbox`, which the
  tests use for the same thing: `Ecto.Migrator` runs each migration in a
  process of its own, and the sandbox gives each process the one
  connection, with a transaction that never commits.

  The migrations of one organisation run after a savepoint, and the
  rehearsal goes back to it before the next organisation. So the locks of
  one organisation are free before the next one takes its own, and a
  fault in one organisation does not hide a fault in the next.

  A new installation has nothing to lose, and is not rehearsed.
  """

  alias Ecto.Adapters.SQL.Sandbox
  alias Rescord.Repo

  @savepoint "rescord_rehearsal"

  @typedoc "A migration: its number, and the name of its file with no `.exs`."
  @type migration :: {version :: integer, name :: String.t()}

  @typedoc "Where a migration runs: the database, or the schema of an organisation with its short name."
  @type scope :: :database | {:organisation, schema :: String.t(), short_name :: String.t()}

  @typedoc "What has not run: in the database, and in each organisation that has such a migration."
  @type plan :: %{
          new?: boolean,
          database: [migration],
          organisations: [{schema :: String.t(), short_name :: String.t(), [migration]}]
        }

  @typedoc "A migration that failed in the rehearsal, with the message and the hint of PostgreSQL."
  @type fault :: %{
          scope: scope,
          migration: migration,
          message: String.t(),
          hint: String.t() | nil
        }

  @type result :: {:nothing, plan} | {:passed, plan} | {:failed, plan, [fault]}

  @doc """
  What an upgrade would run. The repository is started.

  The options are for the tests: `:migrations` and `:tenant_migrations`
  are each a directory or a list of `{version, module}`, and `:tenants` is
  a list of `{schema, short_name}`.
  """
  @spec plan(keyword) :: plan
  def plan(opts \\ []) do
    database_source = database_source(opts)
    done = Ecto.Migrator.migrated_versions(Repo)

    %{
      new?: done == [],
      database: pending(database_source, done),
      organisations:
        for {schema, short_name} <- tenants(opts),
            pending = pending(tenant_source(opts), tenant_versions(schema)),
            pending != [] do
          {schema, short_name, pending}
        end
    }
  end

  @doc "Whether the plan has a migration to rehearse."
  @spec rehearse?(plan) :: boolean
  def rehearse?(%{new?: true}), do: false
  def rehearse?(plan), do: plan.database != [] or plan.organisations != []

  @doc """
  Rehearses the upgrade, and changes nothing. `{:nothing, plan}` for a
  new installation and for a database with each migration run.
  """
  @spec run(keyword) :: result
  def run(opts \\ []) do
    plan = plan(opts)

    if rehearse?(plan) do
      case rehearse(plan, opts) do
        [] -> {:passed, plan}
        faults -> {:failed, plan, faults}
      end
    else
      {:nothing, plan}
    end
  end

  @doc "The lines that tell an operator what the rehearsal did."
  @spec format(result) :: String.t()
  def format({:nothing, _plan}), do: "No upgrade to rehearse."

  def format({:passed, plan}) do
    "The rehearsal of the upgrade passed: #{counts(plan)}. Nothing is changed yet."
  end

  def format({:failed, plan, faults}) do
    """
    The rehearsal of the upgrade failed, and Rescord changed nothing.
    It tried #{counts(plan)}.

    #{Enum.map_join(faults, "\n\n", &format_fault/1)}

    The database is as it was before this start, so the version of Rescord
    that ran before still runs on it. Read the line of each migration above
    in the section "Upgrade notes" of CHANGELOG.md: it says what the
    migration needs. docs/self-hosting.md, "Upgrade", says what to do next.\
    """
  end

  defp format_fault(%{scope: scope, migration: {version, name}} = fault) do
    lines = ["#{version}_#{name}, #{where(scope)}:", "  " <> indent(fault.message)]
    lines = if fault.hint, do: lines ++ ["  " <> indent(fault.hint)], else: lines
    Enum.join(lines, "\n")
  end

  defp indent(text), do: text |> String.trim() |> String.replace("\n", "\n  ")

  defp where(:database), do: "in the database"

  defp where({:organisation, schema, short_name}),
    do: "in the organisation #{short_name} (#{schema})"

  defp counts(plan) do
    tenant =
      plan.organisations |> Enum.map(fn {_, _, pending} -> length(pending) end) |> Enum.sum()

    database =
      if plan.database != [],
        do: "#{count(length(plan.database), "migration")} of the database"

    organisations =
      if tenant > 0 do
        "#{count(tenant, "migration")} in #{count(length(plan.organisations), "organisation")}"
      end

    Shoddy.Strings.join_present([database, organisations], ", and ")
  end

  defp count(1, word), do: "1 #{word}"
  defp count(number, word), do: "#{number} #{word}s"

  # The rehearsal itself: a pool of its own with the sandbox, one connection
  # in a transaction, and a rollback at the end in each case.
  defp rehearse(plan, opts) do
    previous = Repo.get_dynamic_repo()
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    {:ok, pool} = Repo.start_link(name: nil, pool: Sandbox, pool_size: 2)

    try do
      # Ecto compiles the file of a migration each time that it runs it: one
      # time for each organisation here, and one more time for the upgrade.
      Code.put_compiler_option(:ignore_module_conflict, true)
      Repo.put_dynamic_repo(pool)
      :ok = Sandbox.mode(pool, :manual)
      :ok = Sandbox.checkout(pool, ownership_timeout: :infinity)
      :ok = Sandbox.mode(pool, {:shared, self()})

      case run_each(plan.database, database_source(opts), :database, []) do
        nil -> Enum.flat_map(plan.organisations, &rehearse_organisation(&1, opts))
        fault -> [fault]
      end
    after
      Sandbox.checkin(pool)
      Repo.put_dynamic_repo(previous)
      Supervisor.stop(pool)
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end
  end

  defp rehearse_organisation({schema, short_name, pending}, opts) do
    statement!("SAVEPOINT #{@savepoint}")

    fault =
      run_each(pending, tenant_source(opts), {:organisation, schema, short_name}, prefix: schema)

    statement!("ROLLBACK TO SAVEPOINT #{@savepoint}")
    statement!("RELEASE SAVEPOINT #{@savepoint}")

    List.wrap(fault)
  end

  # Without `sandbox_subtransaction: false`, the sandbox puts a savepoint of
  # its own around the statement, and takes ours away with it.
  defp statement!(sql), do: Repo.query!(sql, [], sandbox_subtransaction: false)

  # Runs the migrations in order, and stops at the first one that fails:
  # the next ones need what it did not do.
  defp run_each(pending, source, scope, prefix) do
    Enum.find_value(pending, fn {version, _name} = migration ->
      case run_one(source, version, prefix) do
        :ok -> nil
        {message, hint} -> %{scope: scope, migration: migration, message: message, hint: hint}
      end
    end)
  end

  # No lock: the lock of Ecto is a transaction of the process that waits for
  # the migration, on the one connection that the migration needs.
  defp run_one(source, version, prefix) do
    Ecto.Migrator.run(
      Repo,
      source,
      :up,
      [to: version, migration_lock: false, log: false] ++ prefix
    )

    :ok
  rescue
    error -> words(error)
  catch
    kind, _reason -> {"The migration stopped (#{kind}).", nil}
  end

  # The message and the hint of PostgreSQL, and not its detail: the detail
  # of a row that breaks a rule holds the values of the row, and this text
  # goes to the log of the server (ADR 0077). The message of a data
  # exception (class 22), such as `invalid input syntax for type integer:
  # "..."`, holds the value too, so only its code is written.
  defp words(%Postgrex.Error{postgres: %{pg_code: "22" <> _ = pg_code, code: code}}) do
    {"PostgreSQL refused a value of a row: #{code} (#{pg_code}). " <>
       "Its message holds the value, and is not written here.", nil}
  end

  defp words(%Postgrex.Error{postgres: %{message: message} = postgres}),
    do: {message, postgres[:hint]}

  defp words(%Ecto.MigrationError{message: message}), do: {message, nil}

  defp words(error),
    do: {"The migration stopped with #{inspect(error.__struct__)}.", nil}

  defp pending(source, done) do
    source
    |> available()
    |> Enum.reject(fn {version, _name} -> version in done end)
    |> Enum.sort()
  end

  # The migrations of a source, as Ecto finds them: a file
  # `<number>_<name>.exs`, or a module with its number.
  defp available(source) do
    source
    |> List.wrap()
    |> Enum.flat_map(fn
      directory when is_binary(directory) ->
        for file <- Path.wildcard(Path.join([directory, "**", "*.exs"])),
            {version, "_" <> name} <- [Integer.parse(Path.basename(file, ".exs"))] do
          {version, name}
        end

      {version, module} when is_integer(version) and is_atom(module) ->
        [{version, inspect(module)}]
    end)
  end

  defp database_source(opts),
    do: Keyword.get_lazy(opts, :migrations, fn -> Ecto.Migrator.migrations_path(Repo) end)

  defp tenant_source(opts) do
    Keyword.get_lazy(opts, :tenant_migrations, fn ->
      Ecto.Migrator.migrations_path(Repo, "tenant_migrations")
    end)
  end

  # The schema of each organisation with its short name. The table is not
  # there before its own migration runs.
  defp tenants(opts) do
    Keyword.get_lazy(opts, :tenants, fn ->
      case Repo.query(
             "select 'org_' || id::text, short_name from organisations order by short_name"
           ) do
        {:ok, %{rows: rows}} ->
          Enum.map(rows, fn [schema, short_name] -> {schema, short_name} end)

        {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} ->
          []
      end
    end)
  end

  # The versions that the schema has run. Ecto would make the table of the
  # versions in a schema that has none, so the rehearsal asks first.
  defp tenant_versions(schema) do
    %{rows: [[table?]]} =
      Repo.query!("select to_regclass(format('%I.schema_migrations', $1::text)) is not null", [
        schema
      ])

    if table?, do: Ecto.Migrator.migrated_versions(Repo, prefix: schema), else: []
  end
end
