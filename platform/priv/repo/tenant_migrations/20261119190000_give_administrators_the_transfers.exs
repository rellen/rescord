defmodule Rescord.Repo.TenantMigrations.GiveAdministratorsTheTransfers do
  @moduledoc """
  Gives the role with the key `administrator` the power `transfers`
  (ADR 0042), as ADR 0040 says for each new power. Another role gets it
  when an administrator ticks it.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_append(powers, 'transfers')
    WHERE key = 'administrator' AND NOT ('transfers' = ANY(powers))
    """)
  end

  def down do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_remove(powers, 'transfers')
    """)
  end
end
