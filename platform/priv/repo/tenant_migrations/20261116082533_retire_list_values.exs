defmodule Rescord.Repo.TenantMigrations.RetireListValues do
  @moduledoc """
  Gives each list of an organisation the column `retired`, and gives the
  column of the estimate of a date of birth the name of its attribute
  (ADR 0027).

  `mix ash_postgres.generate_migrations` made this file. We changed the part
  for the residents by hand, to a rename.
  """

  use Ecto.Migration

  def up do
    alter table(:breeds, prefix: prefix()) do
      add :retired, :boolean, null: false, default: false
    end

    alter table(:coats, prefix: prefix()) do
      add :retired, :boolean, null: false, default: false
    end

    alter table(:colours, prefix: prefix()) do
      add :retired, :boolean, null: false, default: false
    end

    alter table(:identifier_kinds, prefix: prefix()) do
      add :retired, :boolean, null: false, default: false
    end

    # The generator wrote a new column and the removal of the old one, which
    # loses each value. A rename keeps them.
    rename table(:residents, prefix: prefix()), :born_on_is_estimated, to: :born_on_estimated

    alter table(:size_classes, prefix: prefix()) do
      add :retired, :boolean, null: false, default: false
    end

    alter table(:species, prefix: prefix()) do
      add :retired, :boolean, null: false, default: false
    end

    alter table(:temperaments, prefix: prefix()) do
      add :retired, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:temperaments, prefix: prefix()) do
      remove :retired
    end

    alter table(:species, prefix: prefix()) do
      remove :retired
    end

    alter table(:size_classes, prefix: prefix()) do
      remove :retired
    end

    rename table(:residents, prefix: prefix()), :born_on_estimated, to: :born_on_is_estimated

    alter table(:identifier_kinds, prefix: prefix()) do
      remove :retired
    end

    alter table(:colours, prefix: prefix()) do
      remove :retired
    end

    alter table(:coats, prefix: prefix()) do
      remove :retired
    end

    alter table(:breeds, prefix: prefix()) do
      remove :retired
    end
  end
end
