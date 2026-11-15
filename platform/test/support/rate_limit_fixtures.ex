defmodule Rescord.RateLimitFixtures do
  @moduledoc """
  A resource in memory with a rate limit on one action.
  `Rescord.RateLimitTest` reads how the limit behaves.
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule Request do
    @moduledoc false
    # Not `Rescord.Resource`: this resource has no table in PostgreSQL.
    use Ash.Resource,
      domain: Rescord.RateLimitFixtures.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshRateLimiter]

    rate_limit do
      backend Rescord.RateLimit

      # One bucket for each address, as a request for a sign-in link has.
      action :create,
        limit: 2,
        per: :timer.minutes(1),
        key: fn changeset ->
          "test/request?" <> Ash.Changeset.get_attribute(changeset, :address)
        end
    end

    actions do
      defaults [:read, create: [:address]]
    end

    attributes do
      uuid_primary_key :id
      attribute :address, :string, public?: true, allow_nil?: false
    end
  end
end
