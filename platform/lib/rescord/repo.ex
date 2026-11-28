defmodule Rescord.Repo do
  use AshPostgres.Repo,
    otp_app: :rescord

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    # A temporal resource needs btree_gist for its primary key (ADR 0012).
    # The email address of a user compares without case, which needs citext.
    # An amount of an expense is the composite type of AshMoney (ADR 0082).
    ["ash-functions", "btree_gist", "citext", AshMoney.AshPostgresExtension]
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end

  # The schemas of the organisations (ADR 0011), for the tenant migrations.
  # The table is not there before its own migration runs.
  @impl true
  def all_tenants do
    case query("select 'org_' || id::text from organisations") do
      {:ok, %{rows: rows}} -> List.flatten(rows)
      {:error, %Postgrex.Error{postgres: %{code: :undefined_table}}} -> []
    end
  end

  @impl true
  def min_pg_version do
    %Version{major: 18, minor: 0, patch: 0}
  end
end
