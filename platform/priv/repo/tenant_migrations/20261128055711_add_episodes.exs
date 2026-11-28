defmodule Rescord.Repo.TenantMigrations.AddEpisodes do
  @moduledoc """
  Adds the conditions of a resident (ADR 0083): the table `episodes`, and
  the column `episode_id` of `journal_entries`, which names the episode that
  an entry is about.

  It changes no row. The new column is empty in each entry that is there,
  in each version of it, so the new foreign key holds for each of them. A
  diagnosis that is in a journal already gets no episode: a member starts
  one in the journal.

  `down` removes the table and the column, with each episode that the
  members recorded.
  """

  use Ecto.Migration

  def up do
    create table(:episodes, primary_key: false, prefix: prefix()) do
      add :changes, :map
      add :version_action_name, :text
      add :version_action_type, :text
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()")
      add :started_on, :date, null: false
      add :ended_on, :date
      add :chronic, :boolean, null: false, default: false
      add :note, :text
      add :user_id, :uuid
      add :resident_id, :uuid, null: false
      add :condition_id, :uuid, null: false
      add :valid_at, :tstzrange, null: false
    end

    execute(
      "ALTER TABLE \"#{prefix()}\".\"episodes\" ADD PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)"
    )

    alter table(:episodes, prefix: prefix()) do
      add :archived_at, :utc_datetime_usec
    end

    execute(
      "ALTER TABLE \"#{prefix()}\".\"episodes\" ADD CONSTRAINT episodes_resident_id_fkey FOREIGN KEY (resident_id, PERIOD valid_at) REFERENCES \"#{prefix()}\".\"residents\" (id, PERIOD valid_at)"
    )

    execute(
      "ALTER TABLE \"#{prefix()}\".\"episodes\" ADD CONSTRAINT episodes_condition_id_fkey FOREIGN KEY (condition_id, PERIOD valid_at) REFERENCES \"#{prefix()}\".\"conditions\" (id, PERIOD valid_at)"
    )

    alter table(:journal_entries, prefix: prefix()) do
      add :episode_id, :uuid
    end

    execute(
      "ALTER TABLE \"#{prefix()}\".\"journal_entries\" ADD CONSTRAINT journal_entries_episode_id_fkey FOREIGN KEY (episode_id, PERIOD valid_at) REFERENCES \"#{prefix()}\".\"episodes\" (id, PERIOD valid_at)"
    )
  end

  def down do
    execute("ALTER TABLE \"#{prefix()}\".\"journal_entries\" DROP CONSTRAINT journal_entries_episode_id_fkey")

    alter table(:journal_entries, prefix: prefix()) do
      remove :episode_id
    end

    execute("ALTER TABLE \"#{prefix()}\".\"episodes\" DROP CONSTRAINT episodes_condition_id_fkey")

    execute("ALTER TABLE \"#{prefix()}\".\"episodes\" DROP CONSTRAINT episodes_resident_id_fkey")

    alter table(:episodes, prefix: prefix()) do
      remove :archived_at
    end

    drop table(:episodes, prefix: prefix())
  end
end
