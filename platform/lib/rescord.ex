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
    exports: [Repo],
    check: [aliases: true, apps: [:phoenix, :phoenix_live_view, :phoenix_html, :shoddy_phoenix]]
end
