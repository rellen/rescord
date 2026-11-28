defmodule Rescord.Repo.TenantMigrations.AddTheErasureOfAMember do
  @moduledoc """
  The erasure of a member on request (ADR 0105), in each organisation:
  four new columns of `members` (`erased_at`, `former_number`, which is
  unique, `held_until` and `encrypted_held_email`), all empty on the rows
  that are there; the new tables `privacy_requests` and
  `privacy_settings`, and their versions. No row changes.

  Written by `mix ash.codegen`, and read.
  """

  use Ecto.Migration

  def up do
    alter table(:members, prefix: prefix()) do
      add :erased_at, :utc_datetime_usec
      add :former_number, :bigint
      add :held_until, :date
      add :encrypted_held_email, :binary
    end

    create unique_index(:members, [:former_number], name: "members_unique_former_number_index")

    create table(:privacy_requests_versions, primary_key: false, prefix: prefix()) do
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
            name: "privacy_requests_versions_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nothing,
            on_update: :update_all
          )
    end

    create table(:privacy_requests, primary_key: false, prefix: prefix()) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
    end

    alter table(:privacy_requests_versions, prefix: prefix()) do
      modify :version_source_id,
             references(:privacy_requests,
               column: :id,
               name: "privacy_requests_versions_version_source_id_fkey",
               type: :uuid,
               prefix: prefix()
             )
    end

    create index(:privacy_requests_versions, [:correlation_id],
             where: "correlation_id IS NOT NULL"
           )

    alter table(:privacy_requests, prefix: prefix()) do
      add :user_id, :uuid, null: false
      add :member_id, :uuid, null: false
      add :author_id, :uuid
      add :how_received, :text, null: false, default: "own_page"
      add :identity, :text
      add :received_on, :date, null: false
      add :identity_confirmed_on, :date
      add :due_on, :date, null: false
      add :extended_to, :date
      add :extension_reason, :text
      add :told_of_extension_on, :date
      add :state, :text, null: false, default: "received"
      add :refusal_reason, :text
      add :kept, :text
      add :keep_comments, :boolean
      add :former_number, :bigint
      add :correlation_id, :uuid
      add :told_on, :date
      add :closed_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :encrypted_contact, :binary
    end

    create index(:privacy_requests, [:state])

    create index(:privacy_requests, [:user_id])

    create table(:privacy_settings, primary_key: false, prefix: prefix()) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :which, :text, null: false, default: "settings"
      add :money_years, :bigint, null: false, default: 7
      add :pseudonymise_after_months, :bigint
      add :closed_request_years, :bigint, null: false, default: 3
      add :contact_name, :text
      add :contact_email, :citext
      add :authority, :text
      add :notice_text, :text

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:privacy_settings, [:which], name: "privacy_settings_one_row_index")

    create table(:privacy_settings_versions, primary_key: false, prefix: prefix()) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :version_action_type, :text, null: false
      add :version_action_name, :text, null: false
      add :correlation_id, :uuid
      add :operation_id, :uuid
      add :causation_id, :uuid

      add :version_source_id,
          references(:privacy_settings,
            column: :id,
            name: "privacy_settings_versions_version_source_id_fkey",
            type: :uuid,
            prefix: prefix()
          ), null: false

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
            name: "privacy_settings_versions_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nothing,
            on_update: :update_all
          )
    end

    create index(:privacy_settings_versions, [:correlation_id],
             where: "correlation_id IS NOT NULL"
           )
  end

  def down do
    drop_if_exists index(:privacy_settings_versions, [:correlation_id])

    drop constraint(:privacy_settings_versions, "privacy_settings_versions_user_id_fkey")

    drop constraint(
           :privacy_settings_versions,
           "privacy_settings_versions_version_source_id_fkey"
         )

    drop table(:privacy_settings_versions, prefix: prefix())

    drop_if_exists unique_index(:privacy_settings, [:which],
                     name: "privacy_settings_one_row_index"
                   )

    drop table(:privacy_settings, prefix: prefix())

    drop_if_exists index(:privacy_requests, [:user_id])

    drop_if_exists index(:privacy_requests, [:state])

    alter table(:privacy_requests, prefix: prefix()) do
      remove :encrypted_contact
      remove :inserted_at
      remove :closed_at
      remove :told_on
      remove :correlation_id
      remove :former_number
      remove :keep_comments
      remove :kept
      remove :refusal_reason
      remove :state
      remove :told_of_extension_on
      remove :extension_reason
      remove :extended_to
      remove :due_on
      remove :identity_confirmed_on
      remove :received_on
      remove :identity
      remove :how_received
      remove :author_id
      remove :member_id
      remove :user_id
    end

    drop_if_exists index(:privacy_requests_versions, [:correlation_id])

    drop constraint(:privacy_requests_versions, "privacy_requests_versions_user_id_fkey")

    drop constraint(
           :privacy_requests_versions,
           "privacy_requests_versions_version_source_id_fkey"
         )

    alter table(:privacy_requests_versions, prefix: prefix()) do
      modify :version_source_id, :uuid
    end

    drop table(:privacy_requests, prefix: prefix())

    drop table(:privacy_requests_versions, prefix: prefix())

    drop_if_exists unique_index(:members, [:former_number],
                     name: "members_unique_former_number_index"
                   )

    alter table(:members, prefix: prefix()) do
      remove :encrypted_held_email
      remove :held_until
      remove :former_number
      remove :erased_at
    end
  end
end
