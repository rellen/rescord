defmodule Rescord.Repo.Migrations.TransferFilesInAJob do
  @moduledoc """
  Gives a transfer what the job that copies its files needs (ADR 0100):
  the sources of the files while they are copied, how many files the copy
  names, how many are copied, and why a transfer failed.

  It changes no row. Each transfer that is there keeps its state, has no
  sources, and counts 0 files: its files were copied in its send, and the
  file check (ADR 0091) names each file of its copy, as before. The states
  are text, so the two new states `sending` and `failed` need no change of
  a column.

  `down` removes the four columns, and what they hold of a transfer that
  is `sending` or `failed`.
  """

  use Ecto.Migration

  def up do
    alter table(:transfers) do
      add :sources, {:array, :map}
      add :files_total, :bigint, null: false, default: 0
      add :files_copied, :bigint, null: false, default: 0
      add :failure, :text
    end
  end

  def down do
    alter table(:transfers) do
      remove :failure
      remove :files_copied
      remove :files_total
      remove :sources
    end
  end
end
