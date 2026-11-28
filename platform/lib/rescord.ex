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
    exports: [
      Dosage,
      Dosage.Result,
      History,
      Images,
      Images.Limit,
      Log,
      Mailer,
      Metrics,
      RateLimit,
      Repo,
      Resource,
      Resource.Checks,
      # `Rescord.Resource` names it in each resource of a domain, and a domain
      # checks such a name too (ADR 0066).
      Resource.VersionPolicies,
      Storage,
      Storage.Compare,
      Storage.Move,
      Storage.Named,
      Storage.Upload,
      Units,
      Units.Quantity,
      Units.Types.Quantity,
      Units.Types.Unit,
      Units.Unit
    ],
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

  @doc """
  The version of Rescord that runs, such as `"0.2.0"`: the version of
  `mix.exs`, which a release carries (ADR 0060). `bin/check` and the page
  of a root user show it.
  """
  @spec version() :: String.t()
  def version, do: :rescord |> Application.spec(:vsn) |> to_string()
end
