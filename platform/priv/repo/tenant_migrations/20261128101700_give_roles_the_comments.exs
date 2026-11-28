defmodule Rescord.Repo.TenantMigrations.GiveRolesTheComments do
  @moduledoc """
  Gives the two first roles of an organisation the powers of the comments
  (issue 29, ADR 0106), as ADR 0040 says for each new power:

    * the role with the key `administrator` gets `comments` and
      `moderate_comments`;
    * the role with the key `member` gets `comments`.

  Another role gets a power when an administrator ticks it. A role that has
  a power already stays as it is, so the statements can run again.

  `down` takes both powers from each role, also from a role that an
  administrator gave one to. SQL writes nothing in the paper trail of a
  role.
  """

  use Ecto.Migration

  def up do
    for {key, power} <- [
          {"administrator", "comments"},
          {"administrator", "moderate_comments"},
          {"member", "comments"}
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
    SET powers = array_remove(array_remove(powers, 'comments'), 'moderate_comments')
    """)
  end
end
