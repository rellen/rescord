defmodule Rescord.Repo.TenantMigrations.GiveAdministratorsThePrivacy do
  @moduledoc """
  Gives the role with the key `administrator` the power `privacy`
  (ADR 0105), as ADR 0040 says for each new power. Another role gets it
  when an administrator ticks it.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_append(powers, 'privacy')
    WHERE key = 'administrator' AND NOT ('privacy' = ANY(powers))
    """)
  end

  def down do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_remove(powers, 'privacy')
    """)
  end
end
