defmodule Rescord.Repo do
  use AshPostgres.Repo,
    otp_app: :rescord

  @impl true
  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    # A temporal resource needs btree_gist for its primary key (ADR 0012).
    # The email address of a user compares without case, which needs citext.
    ["ash-functions", "btree_gist", "citext"]
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  @impl true
  def prefer_transaction? do
    false
  end

  @impl true
  def min_pg_version do
    %Version{major: 18, minor: 0, patch: 0}
  end
end
