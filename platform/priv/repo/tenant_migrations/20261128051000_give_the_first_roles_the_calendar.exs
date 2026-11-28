defmodule Rescord.Repo.TenantMigrations.GiveTheFirstRolesTheCalendar do
  @moduledoc """
  Gives the power `calendar` (ADR 0074) to the two roles that each
  organisation starts with: the role with the key `administrator`, as
  ADR 0040 says for each new power, and the role with the key `member`,
  because a feed is for the person who does the tasks. Another role gets it
  when an administrator ticks it.

  A role is not temporal, so the table has one row for each role and no
  history to change. `down` takes the power from each role, also from a
  role that an administrator gave it to.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_append(powers, 'calendar')
    WHERE key IN ('administrator', 'member') AND NOT ('calendar' = ANY(powers))
    """)
  end

  def down do
    execute("""
    UPDATE "#{prefix()}"."roles"
    SET powers = array_remove(powers, 'calendar')
    """)
  end
end
