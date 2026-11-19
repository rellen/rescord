defmodule Rescord.Repo.TenantMigrations.Step1SmallChanges do
  @moduledoc """
  The smaller changes of 18 November 2026 (ADR 0039): the units of a kind
  of measurement, the days before expiry of an item category, the day from
  which a routine counts, and several members for a task and a routine.

  The member of each task and of each routine goes into its new list before
  the old column goes. `down` keeps the first member of each list.
  """

  use Ecto.Migration

  def up do
    alter table(:item_categories, prefix: prefix()) do
      add :soon_days, :bigint
    end

    alter table(:routines, prefix: prefix()) do
      add :assignee_ids, {:array, :uuid}, null: false, default: []
      add :count_from, :text, null: false, default: "first_day"
    end

    copy_members(:routines)

    alter table(:routines, prefix: prefix()) do
      remove :assignee_id
    end

    alter table(:measure_kinds, prefix: prefix()) do
      add :unit_ids, {:array, :uuid}, null: false, default: []
    end

    alter table(:tasks, prefix: prefix()) do
      add :assignee_ids, {:array, :uuid}, null: false, default: []
    end

    copy_members(:tasks)

    alter table(:tasks, prefix: prefix()) do
      remove :assignee_id
    end
  end

  defp copy_members(table) do
    execute("""
    UPDATE \"#{prefix()}\".\"#{table}\"
    SET assignee_ids = ARRAY[assignee_id]
    WHERE assignee_id IS NOT NULL
    """)
  end

  defp first_member(table) do
    execute("""
    UPDATE \"#{prefix()}\".\"#{table}\"
    SET assignee_id = assignee_ids[1]
    """)
  end

  def down do
    alter table(:tasks, prefix: prefix()) do
      add :assignee_id, :uuid
    end

    first_member(:tasks)

    alter table(:tasks, prefix: prefix()) do
      remove :assignee_ids
    end

    alter table(:measure_kinds, prefix: prefix()) do
      remove :unit_ids
    end

    alter table(:routines, prefix: prefix()) do
      add :assignee_id, :uuid
    end

    first_member(:routines)

    alter table(:routines, prefix: prefix()) do
      remove :count_from
      remove :assignee_ids
    end

    alter table(:item_categories, prefix: prefix()) do
      remove :soon_days
    end
  end
end
