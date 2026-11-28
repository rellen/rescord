defmodule Rescord.Health.Result do
  @moduledoc """
  What a check of `Rescord.Health` found last (ADR 0114, issue 38): one row
  for each check and scope. The scope is the server (`organisation_id`
  empty) or one organisation.

  - `level`: `ok`, `note`, `fail` or `unknown` (the check could not run).
  - `count`: how many rows or things the check found.
  - `ids`: at most 20 ids of what it found, so that a root user can find
    the rows. Never a value of a row: no name, no email, no note.
  - `since`: when the level last changed.
  - `unknown_runs`: the runs in a row that could not run. At three the
    level is `fail`.
  - `alerted_at`: when the root users last got an alert for this row.

  In the shared schema, not temporal, with no paper trail and no archive:
  a run writes the row again each hour, and its history says nothing that a
  person did. Only a root user reads the rows. The domain writes them, with
  no actor.
  """

  use Rescord.Resource,
    domain: Rescord.Health,
    shared?: true,
    temporal?: false,
    paper_trail?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  @levels [:ok, :note, :fail, :unknown]

  @doc "The levels of a result, from the best to the worst."
  @spec levels() :: [atom]
  def levels, do: @levels

  postgres do
    table "health_results"

    references do
      reference :organisation, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :record do
      description "Writes what a run of a check found. Only the domain runs it"

      accept [
        :check,
        :organisation_id,
        :level,
        :count,
        :ids,
        :since,
        :unknown_runs,
        :checked_at,
        :duration_ms,
        :alerted_at
      ]

      upsert? true
      upsert_identity :one_result

      upsert_fields [
        :level,
        :count,
        :ids,
        :since,
        :unknown_runs,
        :checked_at,
        :duration_ms,
        :alerted_at
      ]
    end

    destroy :forget do
      description "Deletes the result of a check that Rescord no longer has"
    end

    update :alerted do
      description "When the root users last got an alert for this result. Only the alerts run it"
      accept [:alerted_at]
    end
  end

  # Only a root user. A result comes from the domain, with no actor.
  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :check, :atom do
      allow_nil? false
      public? true
      constraints one_of: Rescord.Health.Checks.names()
      description "The name of the check"
    end

    attribute :level, :atom do
      allow_nil? false
      public? true
      constraints one_of: @levels
    end

    attribute :count, :integer do
      allow_nil? false
      default 0
      public? true
      constraints min: 0
    end

    attribute :ids, {:array, :uuid} do
      allow_nil? false
      default []
      public? true
      constraints max_length: 20
      description "At most 20 ids of what the check found"
    end

    attribute :since, :utc_datetime_usec do
      allow_nil? false
      public? true
      description "When the level last changed"
    end

    attribute :unknown_runs, :integer do
      allow_nil? false
      default 0
      public? true
      constraints min: 0
    end

    attribute :checked_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      description "When the check last ran"
    end

    attribute :duration_ms, :integer do
      allow_nil? false
      default 0
      public? true
      constraints min: 0
    end

    attribute :alerted_at, :utc_datetime_usec do
      public? true
      description "When the root users last got an alert for this result"
    end
  end

  relationships do
    belongs_to :organisation, Rescord.Accounts.Organisation do
      domain Rescord.Accounts
      public? true
      attribute_writable? true
    end
  end

  identities do
    identity :one_result, [:check, :organisation_id], nils_distinct?: false
  end
end
