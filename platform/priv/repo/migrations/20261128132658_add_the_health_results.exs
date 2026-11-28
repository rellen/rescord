defmodule Rescord.Repo.Migrations.AddTheHealthResults do
  @moduledoc """
  The sanity checks (ADR 0114, issue 38): the table of what each check
  found at its last run, one row for each check and for the server or an
  organisation. The table is empty until the first run, and the rows of an
  organisation go with it. It changes no row.

  The way back (`down`) drops the table: the next run writes it again.

  Written by `mix ash.codegen`, and read.
  """

  use Ecto.Migration

  def up do
    create table(:health_results, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :check, :text, null: false
      add :level, :text, null: false
      add :count, :bigint, null: false, default: 0
      add :ids, {:array, :uuid}, null: false, default: []
      add :since, :utc_datetime_usec, null: false
      add :unknown_runs, :bigint, null: false, default: 0
      add :checked_at, :utc_datetime_usec, null: false
      add :duration_ms, :bigint, null: false, default: 0
      add :alerted_at, :utc_datetime_usec

      add :organisation_id,
          references(:organisations,
            column: :id,
            name: "health_results_organisation_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          )
    end

    create unique_index(:health_results, [:check, :organisation_id],
             name: "health_results_one_result_index",
             nulls_distinct: false
           )
  end

  def down do
    drop constraint(:health_results, "health_results_organisation_id_fkey")

    drop_if_exists unique_index(:health_results, [:check, :organisation_id],
                     name: "health_results_one_result_index"
                   )

    drop table(:health_results)
  end
end
