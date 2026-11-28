defmodule Rescord.Repo.TenantMigrations.GiveRolesTheExpenses do
  @moduledoc """
  Gives the two first roles of an organisation the powers of the expenses
  (ADR 0082), as ADR 0040 says for each new power:

    * the role with the key `administrator` gets `expenses` and
      `manage_expenses`;
    * the role with the key `member` gets `expenses`.

  Another role gets a power when an administrator ticks it. A role that has
  a power already stays as it is, so the statements can run again.

  `down` takes both powers from each role, also from a role that an
  administrator gave one to. SQL writes nothing in the paper trail of a
  role.
  """

  use Ecto.Migration

  def up do
    for {key, power} <- [
          {"administrator", "expenses"},
          {"administrator", "manage_expenses"},
          {"member", "expenses"}
        ] do
      execute("""
      UPDATE "#{prefix()}"."roles"
      SET powers = array_append(powers, '#{power}')
      WHERE key = '#{key}' AND NOT ('#{power}' = ANY(powers))
      """)
    end
  end

  def down do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_remove(array_remove(powers, 'expenses'), 'manage_expenses')
    """)
  end
end
