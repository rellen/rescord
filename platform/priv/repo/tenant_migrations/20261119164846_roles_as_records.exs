defmodule Rescord.Repo.TenantMigrations.RolesAsRecords do
  @moduledoc """
  The roles of an organisation become records (ADR 0040).

  `up` makes the table of the roles with its two roles: `Administrator`,
  with each power, and `Member`, with the powers of a member of ADR 0021.
  It gives each member the role of its old column, and then removes that
  column. `down` gives each member the key of its role again.

  The powers here are those of `Rescord.Accounts.Grants.default_powers/1`
  on the day of this migration. A test holds the two roles of a new
  organisation to that function.
  """

  use Ecto.Migration

  @administrator ~w(members roles settings lists residents remove_residents placements locations journal correct_journal tasks routines stock inventory)
  @member ~w(residents placements journal tasks stock)

  def up do
    create table(:roles, primary_key: false, prefix: prefix()) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :citext, null: false
      add :powers, {:array, :text}, null: false, default: []
      add :key, :text
      add :archived_at, :utc_datetime_usec
    end

    create unique_index(:roles, [:name],
             name: "roles_unique_name_index",
             where: "(archived_at IS NULL)"
           )

    execute("""
    INSERT INTO "#{prefix()}"."roles" (name, powers, key) VALUES
      ('Administrator', ARRAY[#{list(@administrator)}]::text[], 'administrator'),
      ('Member', ARRAY[#{list(@member)}]::text[], 'member')
    """)

    alter table(:members, prefix: prefix()) do
      add :role_id,
          references(:roles,
            column: :id,
            name: "members_role_id_fkey",
            type: :uuid,
            prefix: prefix()
          )
    end

    execute("""
    UPDATE "#{prefix()}"."members" AS m
    SET role_id = r.id
    FROM "#{prefix()}"."roles" AS r
    WHERE r.key = m.role
    """)

    alter table(:members, prefix: prefix()) do
      modify :role_id, :uuid, null: false
      remove :role
    end

    create table(:roles_versions, primary_key: false, prefix: prefix()) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :version_action_type, :text, null: false
      add :version_action_name, :text, null: false

      add :version_source_id,
          references(:roles,
            column: :id,
            name: "roles_versions_version_source_id_fkey",
            type: :uuid,
            prefix: prefix()
          ),
          null: false

      add :changes, :map

      add :version_inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :version_updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :user_id,
          references(:users,
            column: :id,
            name: "roles_versions_user_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :nothing,
            on_update: :update_all
          )
    end
  end

  def down do
    drop constraint(:roles_versions, "roles_versions_user_id_fkey")

    drop constraint(:roles_versions, "roles_versions_version_source_id_fkey")

    drop table(:roles_versions, prefix: prefix())

    drop_if_exists unique_index(:roles, [:name], name: "roles_unique_name_index")

    alter table(:members, prefix: prefix()) do
      add :role, :text, null: false, default: "member"
    end

    execute("""
    UPDATE "#{prefix()}"."members" AS m
    SET role = CASE r.key WHEN 'administrator' THEN 'administrator' ELSE 'member' END
    FROM "#{prefix()}"."roles" AS r
    WHERE r.id = m.role_id
    """)

    drop constraint(:members, "members_role_id_fkey")

    alter table(:members, prefix: prefix()) do
      remove :role_id
    end

    drop table(:roles, prefix: prefix())
  end

  defp list(powers), do: Enum.map_join(powers, ", ", &"'#{&1}'")
end
