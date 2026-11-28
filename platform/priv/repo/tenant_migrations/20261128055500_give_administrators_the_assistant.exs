defmodule Rescord.Repo.TenantMigrations.GiveAdministratorsTheAssistant do
  @moduledoc """
  Gives the role with the key `administrator` the power `ruby` (ADR 0069),
  as ADR 0040 says for each new power. Another role gets it when an
  administrator ticks it. The power alone starts nothing: a member can ask
  the assistant only where the organisation has turned it on.

  A role is not temporal, so the table has one row for each role and no
  history to change. `down` takes the power from each role, also from a
  role that an administrator gave it to.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_append(powers, 'ruby')
    WHERE key = 'administrator' AND NOT ('ruby' = ANY(powers))
    """)
  end

  def down do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_remove(powers, 'ruby')
    """)
  end
end
