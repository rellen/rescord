defmodule Rescord.Repo.Migrations.AddTheSettingsOfTheScan do
  @moduledoc """
  The virus scan of the PDFs (issue 37, ADR 0113): the table of the
  settings of the scan of the server, one row that a root user keeps at
  `/root/scan`, with its history. Both tables are empty, so the scan is off
  until a root user turns it on, and nothing that Rescord does changes.
  It changes no row.

  The way back (`down`) drops the two tables: the settings of the scan go,
  and the scan is off.
  """

  use Ecto.Migration

  def up do
    create table(:scan_settings_versions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :version_action_type, :text, null: false
      add :version_action_name, :text, null: false
      add :correlation_id, :uuid
      add :operation_id, :uuid
      add :causation_id, :uuid
      add :version_source_id, :uuid, null: false
      add :changes, :map

      add :version_inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :version_updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "scan_settings_versions_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nothing,
            on_update: :update_all
          )
    end

    create table(:scan_settings, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:scan_settings_versions) do
      modify :version_source_id,
             references(:scan_settings,
               column: :id,
               name: "scan_settings_versions_version_source_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    create index(:scan_settings_versions, [:correlation_id], where: "correlation_id IS NOT NULL")

    alter table(:scan_settings) do
      add :which, :text, null: false, default: "settings"
      add :scan_on, :boolean, null: false, default: false
      add :address, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:scan_settings, [:which], name: "scan_settings_one_row_index")
  end

  def down do
    drop_if_exists unique_index(:scan_settings, [:which], name: "scan_settings_one_row_index")

    alter table(:scan_settings) do
      remove :updated_at
      remove :inserted_at
      remove :address
      remove :scan_on
      remove :which
    end

    drop_if_exists index(:scan_settings_versions, [:correlation_id])

    drop constraint(:scan_settings_versions, "scan_settings_versions_user_id_fkey")

    drop constraint(:scan_settings_versions, "scan_settings_versions_version_source_id_fkey")

    alter table(:scan_settings_versions) do
      modify :version_source_id, :uuid
    end

    drop table(:scan_settings)

    drop table(:scan_settings_versions)
  end
end
