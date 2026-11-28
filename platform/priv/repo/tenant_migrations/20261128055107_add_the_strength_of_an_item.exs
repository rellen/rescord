defmodule Rescord.Repo.TenantMigrations.AddTheStrengthOfAnItem do
  @moduledoc """
  Adds the strength of an item of the inventory (ADR 0072): the mass of a
  medication in each mL or in each tablet, as a map with the number and
  the unit. The column is empty for each item that is there. `down` removes
  the column with each strength that the members wrote.
  """

  use Ecto.Migration

  def up do
    alter table(:items, prefix: prefix()) do
      add :strength, :map
    end
  end

  def down do
    alter table(:items, prefix: prefix()) do
      remove :strength
    end
  end
end
