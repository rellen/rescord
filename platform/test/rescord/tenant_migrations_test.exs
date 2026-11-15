defmodule Rescord.TenantMigrationsTest do
  @moduledoc """
  Holds the migrations of the schemas of the organisations to the rule of
  `Rescord.TenantMigrations` (ADR 0025): no raw statement has a table with no
  schema, and none refers to a table of the organisation in `public`.
  """

  use ExUnit.Case, async: true

  alias Rescord.TenantMigrations

  test "no tenant migration has a fault" do
    assert Path.wildcard("priv/repo/tenant_migrations/*.exs") != []
    assert TenantMigrations.faults() == []
  end

  test "a repair gives a bare table the schema of the tenant" do
    text = ~S|execute("ALTER TABLE \"arrivals\" ADD CONSTRAINT x FOREIGN KEY (a)")|

    assert TenantMigrations.repair(text, []) ==
             ~S|execute("ALTER TABLE \"#{prefix()}\".\"arrivals\" ADD CONSTRAINT x FOREIGN KEY (a)")|
  end

  test "a repair moves a reference to a table of the organisation out of public" do
    text = ~S|REFERENCES \"public\".\"residents\" (id, PERIOD valid_at)|

    assert TenantMigrations.repair(text, ["residents"]) ==
             ~S|REFERENCES \"#{prefix()}\".\"residents\" (id, PERIOD valid_at)|
  end

  test "a repair leaves a reference to a shared table in public" do
    text = ~S|REFERENCES \"public\".\"base_breeds\" (id, PERIOD valid_at)|

    assert TenantMigrations.repair(text, ["residents"]) == text
  end

  test "a repair changes nothing in a text that it repaired" do
    text = ~S|"ALTER TABLE \"arrivals\" ADD x REFERENCES \"public\".\"residents\" (id)"|
    repaired = TenantMigrations.repair(text, ["residents"])

    assert repaired != text
    assert TenantMigrations.repair(repaired, ["residents"]) == repaired
  end
end
