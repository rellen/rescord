defmodule Rescord.Release.MigrationRulesTest do
  @moduledoc """
  Reads the migrations of `priv/repo`, and holds the rules that the
  rehearsal of an upgrade needs (ADR 0081, `docs/migrations.md`).
  """

  use ExUnit.Case, async: true

  @files Path.wildcard("priv/repo/{migrations,tenant_migrations}/*.exs")

  test "finds the migrations" do
    assert length(@files) > 30
  end

  # A statement that PostgreSQL refuses inside a transaction cannot run in
  # the rehearsal, which is one transaction.
  test "no migration leaves its transaction" do
    outside =
      for file <- @files,
          text = File.read!(file),
          text =~ "@disable_ddl_transaction" or text =~ ~r/\bCONCURRENTLY\b/i or
            text =~ "concurrently: true",
          do: file

    assert outside == []
  end

  # The real run takes the lock of Ecto, so that two starts do not migrate at
  # one time.
  test "no migration turns the lock of the migrations off" do
    assert Enum.filter(@files, &(File.read!(&1) =~ "@disable_migration_lock")) == []
  end
end
