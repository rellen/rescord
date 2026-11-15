defmodule Rescord.TenantMigrations do
  @moduledoc """
  Repairs the migrations of the schemas of the organisations (ADR 0025).

  ash_postgres 2.15.2 writes the period foreign key of a temporal resource as
  a raw statement, with two faults in a tenant migration:

    * the table of the statement has no schema, so PostgreSQL looks for it
      outside the schema of the organisation;
    * a table of the organisation that the key refers to has the schema
      `public`.

  With either fault no organisation can be created. After `mix ash.codegen`
  makes a tenant migration, run:

      mix run --no-start -e "Rescord.TenantMigrations.repair!()"

  `Rescord.TenantMigrationsTest` fails while a migration has a fault.
  """

  @migrations "priv/repo/tenant_migrations/*.exs"
  @snapshots "priv/resource_snapshots/repo/tenants/*"

  # In the text of a migration: ALTER TABLE \"table\" with no schema before it.
  @bare_table ~r/ALTER TABLE \\"([a-z_]+)\\" /
  # In the text of a migration: REFERENCES \"public\".\"table\".
  @public_reference ~r/REFERENCES \\"public\\"\.\\"([a-z_]+)\\"/

  @doc "The lines of the tenant migrations that have a fault, each as `{file, line}`."
  @spec faults() :: [{String.t(), String.t()}]
  def faults do
    tables = tenant_tables()

    for file <- files(),
        line <- file |> File.read!() |> String.split("\n"),
        faulty?(line, tables) do
      {file, String.trim(line)}
    end
  end

  @doc "Repairs each tenant migration, and returns the files that it changed."
  @spec repair!() :: [String.t()]
  def repair! do
    tables = tenant_tables()

    for file <- files(),
        text = File.read!(file),
        repaired = repair(text, tables),
        repaired != text do
      File.write!(file, repaired)
      file
    end
  end

  @doc "The text of a migration with its faults repaired."
  @spec repair(String.t(), [String.t()]) :: String.t()
  def repair(text, tables) do
    text = Regex.replace(@bare_table, text, ~S|ALTER TABLE \\"#{prefix()}\\".\\"\1\\" |)

    Regex.replace(@public_reference, text, fn whole, table ->
      if table in tables, do: ~S|REFERENCES \"#{prefix()}\".\"| <> table <> ~S|\"|, else: whole
    end)
  end

  defp faulty?(line, tables) do
    Regex.match?(@bare_table, line) or
      Enum.any?(Regex.scan(@public_reference, line), fn [_whole, table] -> table in tables end)
  end

  defp files, do: Path.wildcard(@migrations)

  # A table of an organisation has a directory of snapshots of its own.
  defp tenant_tables, do: @snapshots |> Path.wildcard() |> Enum.map(&Path.basename/1)
end
