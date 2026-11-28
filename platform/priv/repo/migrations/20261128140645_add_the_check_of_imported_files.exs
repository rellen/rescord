defmodule Rescord.Repo.Migrations.AddTheCheckOfImportedFiles do
  @moduledoc """
  The check of the files of an imported transfer (issue 37, ADR 0113): two
  empty columns of the transfers, `files_checked_at`, when a job cleaned
  the photos and scanned the PDFs of an import, and `files_check_failure`,
  why its files failed. The files of an import open only with the first
  set, so the next migration
  (`20261128140700_count_the_imported_files_as_checked`) sets it for each
  import that is there. It changes no row.

  The way back (`down`) drops the two columns.
  """

  use Ecto.Migration

  def up do
    alter table(:transfers) do
      add :files_checked_at, :utc_datetime_usec
      add :files_check_failure, :text
    end
  end

  def down do
    alter table(:transfers) do
      remove :files_check_failure
      remove :files_checked_at
    end
  end
end
