defmodule Rescord.Repo.Migrations.AddThePrivacyNotice do
  @moduledoc """
  The privacy notices (ADR 0105): the table of the privacy settings of the
  server, one row that a root user keeps, with its history, and the column
  `organisations.notice_id`, the random id in the link of the notice of an
  organisation. The new table is empty. The default of the column gives
  each organisation that is there a new random id as the column is added,
  so `NOT NULL` and the unique index hold for each row, and no other value
  changes. The id is not the id of the organisation.

  The way back (`down`) drops the table, its history and the column: the
  settings of the server and each link of a notice go.

  Written by `mix ash.codegen`, and read.
  """

  use Ecto.Migration

  def up do
    create table(:privacy_instance_settings_versions, primary_key: false) do
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
            name: "privacy_instance_settings_versions_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nothing,
            on_update: :update_all
          )
    end

    create table(:privacy_instance_settings, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:privacy_instance_settings_versions) do
      modify :version_source_id,
             references(:privacy_instance_settings,
               column: :id,
               name: "privacy_instance_settings_versions_version_source_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    create index(:privacy_instance_settings_versions, [:correlation_id],
             where: "correlation_id IS NOT NULL"
           )

    alter table(:privacy_instance_settings) do
      add :which, :text, null: false, default: "settings"
      add :operator_name, :text
      add :operator_contact, :text
      add :hosting, :text
      add :mail_provider, :text
      add :backup_days, :bigint, null: false, default: 14

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:privacy_instance_settings, [:which],
             name: "privacy_instance_settings_one_row_index"
           )

    alter table(:organisations) do
      add :notice_id, :uuid, null: false, default: fragment("gen_random_uuid()")
    end

    create unique_index(:organisations, [:notice_id],
             name: "organisations_unique_notice_id_index"
           )
  end

  def down do
    drop_if_exists unique_index(:organisations, [:notice_id],
                     name: "organisations_unique_notice_id_index"
                   )

    alter table(:organisations) do
      remove :notice_id
    end

    drop_if_exists unique_index(:privacy_instance_settings, [:which],
                     name: "privacy_instance_settings_one_row_index"
                   )

    alter table(:privacy_instance_settings) do
      remove :updated_at
      remove :inserted_at
      remove :backup_days
      remove :mail_provider
      remove :hosting
      remove :operator_contact
      remove :operator_name
      remove :which
    end

    drop_if_exists index(:privacy_instance_settings_versions, [:correlation_id])

    drop constraint(
           :privacy_instance_settings_versions,
           "privacy_instance_settings_versions_user_id_fkey"
         )

    drop constraint(
           :privacy_instance_settings_versions,
           "privacy_instance_settings_versions_version_source_id_fkey"
         )

    alter table(:privacy_instance_settings_versions) do
      modify :version_source_id, :uuid
    end

    drop table(:privacy_instance_settings)

    drop table(:privacy_instance_settings_versions)
  end
end
