defmodule Rescord.Release.RehearsalTest do
  @moduledoc """
  Holds the rehearsal of an upgrade (ADR 0081): it finds the migration that
  fails on the rows of one organisation, says so with the words of
  PostgreSQL and without the values of a row, goes on to the next
  organisation, and leaves the database as it was in each case.

  The rehearsal has a connection of its own, which sees only what is
  committed. So these tests make two schemas for real, outside the
  transaction of a test, and remove them at the end. They do not run
  beside others.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Rescord.Release.Rehearsal
  alias Rescord.Repo

  # The tests reach PostgreSQL (ADR 0006), with no transaction of a test.
  @moduletag :postgres

  @tidy "rehearsal_tidy"
  @doubles "rehearsal_doubles"
  @tenants [{@tidy, "tidy-refuge"}, {@doubles, "doubles-refuge"}]

  defmodule AddATown do
    use Ecto.Migration

    def up do
      alter table(:clinics, prefix: prefix()) do
        add :town, :text
      end
    end

    def down do
      alter table(:clinics, prefix: prefix()) do
        remove :town
      end
    end
  end

  defmodule OneNameForAClinic do
    use Ecto.Migration

    def up, do: create(unique_index(:clinics, [:name], prefix: prefix()))
    def down, do: drop(unique_index(:clinics, [:name], prefix: prefix()))
  end

  # The form of `docs/migrations.md`, "A step by hand".
  defmodule CheckThatEachClinicHasOneName do
    use Ecto.Migration

    def up do
      execute("""
      DO $$
      DECLARE
        doubles bigint;
      BEGIN
        SELECT count(*) INTO doubles
        FROM (
          SELECT name FROM "#{prefix()}"."clinics"
          GROUP BY name HAVING count(*) > 1
        ) AS same;

        IF doubles > 0 THEN
          RAISE EXCEPTION 'Rescord cannot upgrade: % names of clinics are used more than one time in the schema %.', doubles, '#{prefix()}'
            USING HINT = 'Do the step "Before the upgrade" of the upgrade notes of this release.';
        END IF;
      END
      $$;
      """)
    end

    def down, do: :ok
  end

  defmodule ANameIsANumber do
    use Ecto.Migration

    def up do
      execute(
        ~s|ALTER TABLE "#{prefix()}"."clinics" ALTER COLUMN name TYPE integer USING name::integer|
      )
    end

    def down, do: :ok
  end

  defmodule AddATableOfTheDatabase do
    use Ecto.Migration

    def up do
      create table(:rehearsal_things) do
        add :name, :text
      end
    end

    def down, do: drop(table(:rehearsal_things))
  end

  defmodule FailInTheDatabase do
    use Ecto.Migration

    def up, do: execute("ALTER TABLE rehearsal_no_such_table ADD COLUMN name text")
    def down, do: :ok
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  defp one!(sql), do: unboxed(fn -> Repo.query!(sql).rows end)

  setup do
    unboxed(fn ->
      for {schema, _name} <- @tenants do
        Repo.query!(~s|DROP SCHEMA IF EXISTS "#{schema}" CASCADE|)
        Repo.query!(~s|CREATE SCHEMA "#{schema}"|)
        Repo.query!(~s|CREATE TABLE "#{schema}"."clinics" (id bigserial PRIMARY KEY, name text)|)
      end

      Repo.query!(~s|INSERT INTO "#{@tidy}"."clinics" (name) VALUES ('North'), ('South')|)

      Repo.query!(
        ~s|INSERT INTO "#{@doubles}"."clinics" (name) VALUES ('Wattle Creek Vets'), ('Wattle Creek Vets')|
      )
    end)

    on_exit(fn ->
      unboxed(fn ->
        for {schema, _name} <- @tenants, do: Repo.query!(~s|DROP SCHEMA "#{schema}" CASCADE|)
      end)
    end)
  end

  # What a rehearsal could leave: a table of the database, a column or an
  # index in a schema, the table of the versions of a schema, and a version.
  defp traces do
    one!("""
    SELECT 'table ' || table_schema || '.' || table_name FROM information_schema.tables
    WHERE table_name = 'rehearsal_things'
       OR (table_schema LIKE 'rehearsal_%' AND table_name <> 'clinics')
    UNION ALL
    SELECT 'column ' || table_schema || '.' || column_name FROM information_schema.columns
    WHERE table_schema LIKE 'rehearsal_%' AND table_name = 'clinics'
      AND column_name NOT IN ('id', 'name')
    UNION ALL
    SELECT 'index ' || schemaname || '.' || indexname FROM pg_indexes
    WHERE schemaname LIKE 'rehearsal_%' AND indexname <> 'clinics_pkey'
    UNION ALL
    SELECT 'version ' || version FROM schema_migrations WHERE version >= 30000101000000
    """)
  end

  defp rehearse(opts) do
    unboxed(fn ->
      Rehearsal.run(Keyword.merge([migrations: [], tenants: @tenants], opts))
    end)
  end

  test "a rehearsal that passes says what it ran, and leaves nothing" do
    result =
      rehearse(
        migrations: [{30_000_101_000_001, AddATableOfTheDatabase}],
        tenant_migrations: [{30_000_101_000_002, AddATown}]
      )

    assert {:passed, plan} = result
    assert [{30_000_101_000_001, _name}] = plan.database
    assert [{@tidy, "tidy-refuge", [_]}, {@doubles, "doubles-refuge", [_]}] = plan.organisations

    assert Rehearsal.format(result) ==
             "The rehearsal of the upgrade passed: 1 migration of the database, and " <>
               "2 migrations in 2 organisations. Nothing is changed yet."

    assert traces() == []
  end

  test "says only what it ran" do
    result =
      rehearse(tenant_migrations: [{30_000_101_000_002, AddATown}], tenants: [hd(@tenants)])

    assert Rehearsal.format(result) ==
             "The rehearsal of the upgrade passed: 1 migration in 1 organisation. " <>
               "Nothing is changed yet."
  end

  test "finds the organisation whose rows a migration fails on, and leaves nothing" do
    result =
      rehearse(
        tenant_migrations: [
          {30_000_101_000_002, AddATown},
          {30_000_101_000_003, OneNameForAClinic}
        ]
      )

    assert {:failed, _plan, [fault]} = result
    assert fault.scope == {:organisation, @doubles, "doubles-refuge"}
    assert {30_000_101_000_003, _name} = fault.migration
    assert fault.message =~ "could not create unique index"

    text = Rehearsal.format(result)
    assert text =~ "in the organisation doubles-refuge (#{@doubles})"
    assert text =~ "Rescord changed nothing"
    # The detail of PostgreSQL holds the name that is there two times.
    refute text =~ "Wattle Creek Vets"

    assert traces() == []
  end

  test "gives the message and the hint of a migration that checks first" do
    result =
      rehearse(
        tenant_migrations: [
          {30_000_101_000_002, CheckThatEachClinicHasOneName},
          {30_000_101_000_003, OneNameForAClinic}
        ]
      )

    assert {:failed, _plan, [fault]} = result
    assert {30_000_101_000_002, _name} = fault.migration

    assert fault.message ==
             "Rescord cannot upgrade: 1 names of clinics are used more than one time " <>
               "in the schema #{@doubles}."

    assert fault.hint =~ ~s|Do the step "Before the upgrade"|
    assert Rehearsal.format(result) =~ fault.hint
    assert traces() == []
  end

  test "writes the code, and not the message, of an error that holds a value" do
    result = rehearse(tenant_migrations: [{30_000_101_000_005, ANameIsANumber}])

    assert {:failed, _plan, [first, _second]} = result
    assert first.message =~ "invalid_text_representation (22P02)"

    text = Rehearsal.format(result)
    refute text =~ "North"
    refute text =~ "Wattle Creek Vets"
    assert traces() == []
  end

  test "names each organisation with a fault, and not only the first" do
    unboxed(fn ->
      Repo.query!(~s|INSERT INTO "#{@tidy}"."clinics" (name) VALUES ('North')|)
    end)

    result = rehearse(tenant_migrations: [{30_000_101_000_003, OneNameForAClinic}])

    assert {:failed, _plan, faults} = result

    assert Enum.map(faults, & &1.scope) == [
             {:organisation, @tidy, "tidy-refuge"},
             {:organisation, @doubles, "doubles-refuge"}
           ]

    assert traces() == []
  end

  test "stops at a fault in the database, before the organisations" do
    result =
      rehearse(
        migrations: [
          {30_000_101_000_001, AddATableOfTheDatabase},
          {30_000_101_000_004, FailInTheDatabase}
        ],
        tenant_migrations: [{30_000_101_000_003, OneNameForAClinic}]
      )

    assert {:failed, _plan, [fault]} = result
    assert fault.scope == :database
    assert fault.message =~ "rehearsal_no_such_table"
    assert Rehearsal.format(result) =~ "30000101000004_"
    assert traces() == []
  end

  test "has nothing to rehearse when each migration has run" do
    assert {:nothing, plan} = unboxed(fn -> Rehearsal.run() end)
    assert plan.database == []
    refute plan.new?
    refute Rehearsal.rehearse?(plan)
  end

  test "does not rehearse a new installation" do
    plan = %{new?: true, database: [{1, "first"}], organisations: []}
    refute Rehearsal.rehearse?(plan)
  end

  test "the command of the release says that it has nothing to rehearse" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        unboxed(fn -> assert :ok = Rescord.Release.rehearse() end)
      end)

    assert output == "No upgrade to rehearse.\n"
  end
end
