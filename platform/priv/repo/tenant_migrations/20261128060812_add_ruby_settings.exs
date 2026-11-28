defmodule Rescord.Repo.TenantMigrations.AddRubySettings do
  @moduledoc """
  Adds the table of the settings of the assistant (ADR 0069) to the schema
  of an organisation: whether Ruby is on, its provider, the place that an
  administrator agreed to, the allowance and the days that a conversation
  is kept. The table is new and empty, so the assistant is off, and no
  other table changes.

  The table is temporal: it keeps each version of its one row, and the
  exclusion on `which` holds the organisation to one row at a time.

  `mix ash_postgres.generate_migrations` wrote the statements.
  """

  use Ecto.Migration

  def up do
    create table(:ruby_settings, primary_key: false, prefix: prefix()) do
      add :changes, :map
      add :version_action_name, :text
      add :version_action_type, :text
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :which, :text, null: false, default: "settings"
      add :enabled, :boolean, null: false, default: false
      add :agreed_destination, :text
      add :agreed_words, :text
      add :agreed_at, :utc_datetime_usec
      add :allowance, :bigint
      add :retention_days, :bigint, null: false, default: 90

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :provider_id, :uuid
      add :valid_at, :tstzrange, null: false
    end

    execute(
      "ALTER TABLE \"#{prefix()}\".\"ruby_settings\" ADD PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)"
    )

    execute(
      "ALTER TABLE \"#{prefix()}\".\"ruby_settings\" ADD CONSTRAINT \"ruby_settings_one_row_index\" EXCLUDE USING gist (which WITH =, valid_at WITH &&)"
    )
  end

  def down do
    execute(
      "ALTER TABLE \"#{prefix()}\".\"ruby_settings\" DROP CONSTRAINT IF EXISTS \"ruby_settings_one_row_index\""
    )

    drop table(:ruby_settings, prefix: prefix())
  end
end
