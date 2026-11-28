defmodule Rescord.Repo.TenantMigrations.AddRubyReportedAt do
  @moduledoc """
  Adds `reported_at` to the messages of Ruby: when a member sent an answer
  that was not right to the administrators (ADR 0069). The column is
  empty, and no row changes.
  """

  use Ecto.Migration

  def up do
    alter table(:ruby_messages, prefix: prefix()) do
      add :reported_at, :utc_datetime_usec
    end
  end

  def down do
    alter table(:ruby_messages, prefix: prefix()) do
      remove :reported_at
    end
  end
end
