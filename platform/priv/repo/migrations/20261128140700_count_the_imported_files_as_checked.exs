defmodule Rescord.Repo.Migrations.CountTheImportedFilesAsChecked do
  @moduledoc """
  Sets `files_checked_at` to the time of the migration for each import that
  is there (issue 37, ADR 0113): a transfer with a partner on another
  server and a refuge of this server that receives it. Its files have been
  open already, and the job of the check runs only for a new import. An
  export, and a transfer between two refuges of this server, need no check,
  and keep `NULL`. The statement writes no version of the paper trail. It
  changes no row that has a value, so it can run a second time.

  The way back (`down`) changes nothing: the way back of
  `20261128140645_add_the_check_of_imported_files` drops the column.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE "transfers"
    SET files_checked_at = (now() AT TIME ZONE 'utc')
    WHERE remote_partner_id IS NOT NULL
      AND to_organisation_id IS NOT NULL
      AND files_checked_at IS NULL
      AND files_check_failure IS NULL
    """)
  end

  def down, do: :ok
end
