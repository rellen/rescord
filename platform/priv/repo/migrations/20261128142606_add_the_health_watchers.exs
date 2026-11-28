defmodule Rescord.Repo.Migrations.AddTheHealthWatchers do
  @moduledoc """
  The alerts of the sanity checks (ADR 0114, issue 38): the table of the
  root users who asked for an alert when a check fails. It is empty until
  a root user asks at `/root/health`, and the row of a person goes with
  the user. It changes no row.

  The way back (`down`) drops the table: each root user who asked would
  ask again.

  Written by `mix ash.codegen`, and read.
  """

  use Ecto.Migration

  def up do
    create table(:health_watchers, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "health_watchers_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:health_watchers, [:user_id], name: "health_watchers_one_watcher_index")
  end

  def down do
    drop constraint(:health_watchers, "health_watchers_user_id_fkey")

    drop_if_exists unique_index(:health_watchers, [:user_id],
                     name: "health_watchers_one_watcher_index"
                   )

    drop table(:health_watchers)
  end
end
