defmodule Rescord.Usage.Count do
  @moduledoc """
  How many times a feature was used on one day, on the whole server
  (ADR 0098): a day in UTC, a feature, a kind, the name of a page, an
  action or a file as the code names it, and a number. It holds nothing of
  a person, of an organisation or of a record.

  One row for each day, feature, kind and item. `Rescord.Usage.flush/0`
  writes the counts of the memory with `add`, an upsert that adds the
  number to the row of the day, so that two nodes can count for one
  server.

  In the shared schema, not temporal, with no paper trail and no archive:
  a count changes each minute, and its history would be the count again.
  Only a root user reads the counts, or deletes them. No person writes one:
  the domain does, with no actor.
  """

  use Rescord.Resource,
    domain: Rescord.Usage,
    shared?: true,
    temporal?: false,
    paper_trail?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  postgres do
    table "usage_counts"
  end

  actions do
    defaults [:read]

    create :add do
      description "Adds `by` to the count of a day, a feature, a kind and an item"
      accept [:day, :feature, :kind, :item]
      argument :by, :integer, allow_nil?: false, constraints: [min: 1]
      upsert? true
      upsert_identity :one_count
      upsert_fields []
      change set_attribute(:count, arg(:by))
      change atomic_update(:count, expr(count + ^arg(:by)))
    end

    destroy :forget do
      description "Deletes a count: each one, at the wish of a root user, or one that is too old"
    end
  end

  # Only a root user. A count comes from the domain, with no actor.
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

    attribute :day, :date do
      allow_nil? false
      public? true
      description "The day, in UTC"
    end

    attribute :feature, :atom do
      allow_nil? false
      public? true
      constraints one_of: Rescord.Usage.Features.all()
      description "A key of the list of the features"
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:page, :action, :file]
      description "A page that opened, an action that a person ran, or a file that Rescord sent"
    end

    attribute :item, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
      description "The page, the action or the file, as the code names it"
    end

    attribute :count, :integer do
      allow_nil? false
      public? true
      constraints min: 0
    end
  end

  identities do
    identity :one_count, [:day, :feature, :kind, :item]
  end
end
