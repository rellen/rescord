defmodule Rescord.Repo.TenantMigrations.AddTheDisplayFiles do
  @moduledoc """
  The key of the display file of a photo (issue 34): a column
  `display_key` in `journal_attachments` and in `photos`, with no value.
  It changes no row: `Rescord.Images.Workers.Complete` fills the column,
  with the file, after the start. A version of Rescord from before it
  ignores the column. `down` drops it, and the display files stay in the
  store, where `bin/check-files` reports them as leftovers.
  """


  use Ecto.Migration

  def up do
    alter table(:journal_attachments, prefix: prefix()) do
      add :display_key, :text
    end

    alter table(:photos, prefix: prefix()) do
      add :display_key, :text
    end
  end

  def down do
    alter table(:photos, prefix: prefix()) do
      remove :display_key
    end

    alter table(:journal_attachments, prefix: prefix()) do
      remove :display_key
    end
  end
end
