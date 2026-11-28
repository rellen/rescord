defmodule Rescord.Repo.Migrations.AddTheUsageCounts do
  @moduledoc """
  The usage counts of the server (ADR 0098): the table of the counts of
  each day, the table of the one row of settings, and the versions of the
  settings. Three new tables in the database; it changes no row.

  Written by `mix ash.codegen`, and read.
  """

  use Ecto.Migration

  def up do
    create table(:usage_counts, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :day, :date, null: false
      add :feature, :text, null: false
      add :kind, :text, null: false
      add :item, :text, null: false
      add :count, :bigint, null: false
    end

    create unique_index(:usage_counts, [:day, :feature, :kind, :item],
             name: "usage_counts_one_count_index"
           )

    create table(:usage_settings, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :which, :text, null: false, default: "settings"
      add :mode, :text, null: false, default: "local"
      add :format, :text, null: false, default: "otlp"
      add :endpoint, :text
      add :token_hint, :text
      add :token_set_at, :utc_datetime_usec
      add :installation_id, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :sending_since, :date
      add :last_sent_day, :date
      add :last_attempt_at, :utc_datetime_usec
      add :last_result, :text
      add :last_status, :bigint
      add :tested_at, :utc_datetime_usec
      add :test_result, :text
      add :test_status, :bigint

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :encrypted_token, :binary
    end

    create unique_index(:usage_settings, [:which], name: "usage_settings_one_row_index")

    create table(:usage_settings_versions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :version_action_type, :text, null: false
      add :version_action_name, :text, null: false

      add :version_source_id,
          references(:usage_settings,
            column: :id,
            name: "usage_settings_versions_version_source_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false

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
            name: "usage_settings_versions_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nothing,
            on_update: :update_all
          )
    end
  end

  def down do
    drop constraint(:usage_settings_versions, "usage_settings_versions_user_id_fkey")

    drop constraint(:usage_settings_versions, "usage_settings_versions_version_source_id_fkey")

    drop table(:usage_settings_versions)

    drop_if_exists unique_index(:usage_settings, [:which], name: "usage_settings_one_row_index")

    drop table(:usage_settings)

    drop_if_exists unique_index(:usage_counts, [:day, :feature, :kind, :item],
                     name: "usage_counts_one_count_index"
                   )

    drop table(:usage_counts)
  end
end
