defmodule Rescord.RateLimit do
  @moduledoc """
  The counts of the rate limits of Rescord (ADR 0020).

  This is a Hammer rate limiter that keeps its counts in an ETS table, so
  each node counts by itself and a restart forgets the counts. The
  application starts it.

  The window slides (ADR 0115): a limit of 30 a minute holds for each
  minute, the last 60 seconds before each call. A fixed window would start
  a new count at the turn of each minute, so a person could make 60 calls
  in two seconds, and a test that ran over the turn would see no limit.
  The table keeps one row for each call that it allowed, until the end of
  its period.

  A resource limits an action with the extension `AshRateLimiter`, and names
  this module as the backend:

      use Rescord.Resource,
        domain: Rescord.Accounts,
        extensions: [AshRateLimiter]

      rate_limit do
        backend Rescord.RateLimit
        action :request_sign_in_link, limit: 5, per: :timer.minutes(15)
      end

  An action over its limit returns an `AshRateLimiter.LimitExceeded` error,
  which Ash reports as forbidden.

  Code that is not an Ash action can count with `hit/3`, for example a plug
  that limits the requests of one client.
  """

  use Hammer, backend: :ets, algorithm: :sliding_window
end
