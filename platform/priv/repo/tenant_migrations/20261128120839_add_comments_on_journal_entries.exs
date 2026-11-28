defmodule Rescord.Repo.TenantMigrations.AddCommentsOnJournalEntries do
  @moduledoc """
  A comment and a follow can name a journal entry (issue 29, ADR 0106): a
  column `journal_entry_id` in `comments` and in `comment_follows`, its
  index, and the check that a row names exactly one record, now of five.
  The unique index of a follow takes the new column.

  Each row that is there names one record of the four, so it keeps to the
  new check, and no row changes. A journal entry is temporal, so the column
  has no foreign key, as the column of a resident has none (ADR 0032).
  `down` fails while a comment or a follow names an entry, because the old
  check counts four columns: delete those rows first.
  """

  use Ecto.Migration

  def up do
    alter table(:comments, prefix: prefix()) do
      add :journal_entry_id, :uuid
    end

    drop_if_exists constraint(:comments, :one_record)

    create constraint(:comments, :one_record,
             check: """
               num_nonnulls(resident_id, task_id, expense_id, transfer_id, journal_entry_id) = 1
             """
           )

    create index(:comments, [:journal_entry_id], where: "journal_entry_id IS NOT NULL")

    drop_if_exists unique_index(
                     :comment_follows,
                     [:user_id, :resident_id, :task_id, :expense_id, :transfer_id],
                     name: "comment_follows_one_follow_index"
                   )

    alter table(:comment_follows, prefix: prefix()) do
      add :journal_entry_id, :uuid
    end

    create unique_index(
             :comment_follows,
             [:user_id, :resident_id, :task_id, :expense_id, :transfer_id, :journal_entry_id],
             name: "comment_follows_one_follow_index",
             nulls_distinct: false
           )

    drop_if_exists constraint(:comment_follows, :one_record)

    create constraint(:comment_follows, :one_record,
             check: """
               num_nonnulls(resident_id, task_id, expense_id, transfer_id, journal_entry_id) = 1
             """
           )

    create index(:comment_follows, [:journal_entry_id], where: "journal_entry_id IS NOT NULL")
  end

  def down do
    drop_if_exists index(:comment_follows, [:journal_entry_id])

    drop_if_exists constraint(:comment_follows, :one_record)

    create constraint(:comment_follows, :one_record,
             check: """
               num_nonnulls(resident_id, task_id, expense_id, transfer_id) = 1
             """
           )

    drop_if_exists unique_index(
                     :comment_follows,
                     [
                       :user_id,
                       :resident_id,
                       :task_id,
                       :expense_id,
                       :transfer_id,
                       :journal_entry_id
                     ], name: "comment_follows_one_follow_index")

    alter table(:comment_follows, prefix: prefix()) do
      remove :journal_entry_id
    end

    create unique_index(
             :comment_follows,
             [:user_id, :resident_id, :task_id, :expense_id, :transfer_id],
             name: "comment_follows_one_follow_index",
             nulls_distinct: false
           )

    drop_if_exists index(:comments, [:journal_entry_id])

    drop_if_exists constraint(:comments, :one_record)

    create constraint(:comments, :one_record,
             check: """
               num_nonnulls(resident_id, task_id, expense_id, transfer_id) = 1
             """
           )

    alter table(:comments, prefix: prefix()) do
      remove :journal_entry_id
    end
  end
end
