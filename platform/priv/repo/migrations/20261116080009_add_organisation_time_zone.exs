defmodule Rescord.Repo.Migrations.AddOrganisationTimeZone do
  @moduledoc """
  Gives each organisation a time zone (ADR 0026).

  `mix ash_postgres.generate_migrations` made this file. We changed `up` by
  hand: an organisation that is there already gets `Etc/UTC`, because the
  column takes no empty value. An administrator of the organisation then
  sets the real zone on its settings page.
  """

  use Ecto.Migration

  def up do
    alter table(:organisations) do
      add :time_zone, :text
    end

    execute("UPDATE organisations SET time_zone = 'Etc/UTC' WHERE time_zone IS NULL")

    alter table(:organisations) do
      modify :time_zone, :text, null: false
    end
  end

  def down do
    alter table(:organisations) do
      remove :time_zone
    end
  end
end
