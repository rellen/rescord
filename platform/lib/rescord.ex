defmodule Rescord do
  @moduledoc """
  The core of Rescord: everything that is not the web layer.

  This module is the boundary of the core (ADR 0009). The modules under
  `Rescord` that are not an Ash domain belong to it: the repo, the mailer and
  whatever plain modules join them. Each Ash domain is a boundary of its own,
  which `AshBoundary` declares from the domain.

  The core does not use Phoenix: the compiler rejects a reference from it to
  `:phoenix`, `:phoenix_live_view`, `:phoenix_html` or `:shoddy_phoenix`.
  `Phoenix.PubSub` is the separate application `:phoenix_pubsub`, which the
  core may use.
  """

  use Boundary,
    deps: [],
    exports: [History, Mailer, RateLimit, Repo, Resource, Resource.Checks, Storage],
    check: [aliases: true, apps: [:phoenix, :phoenix_live_view, :phoenix_html, :shoddy_phoenix]]

  @doc """
  Whether Rescord can serve a request: the database answers a query. The
  health endpoint of a container or a service manager asks this.
  """
  @spec healthy?() :: boolean
  def healthy? do
    match?({:ok, _result}, Rescord.Repo.query("select 1", [], timeout: 2_000))
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end
end
