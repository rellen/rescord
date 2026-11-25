defmodule Rescord.Repo.TenantMigrations.GiveAdministratorsTheExport do
  @moduledoc """
  Gives the role with the key `administrator` the power `export` (ADR 0054),
  as ADR 0040 says for each new power. Another role gets it when an
  administrator ticks it.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_append(powers, 'export')
    WHERE key = 'administrator' AND NOT ('export' = ANY(powers))
    """)
  end

  def down do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_remove(powers, 'export')
    """)
  end
end
