defmodule Rescord.Health.Watcher do
  @moduledoc """
  A root user who asked for an alert when a sanity check fails (ADR 0114,
  issue 38, section 9). The alert goes on each channel that the person set
  up and that the server has: each device of Web Push, and the topic of
  ntfy (`Rescord.Notifications.Channel`).

  One row for each person, with nothing but the person. A root user starts
  and stops their own watch at `/root/health`. The row goes with the user,
  and the alerts skip a person who is no root user now.

  In the shared schema, not temporal, with no paper trail and no archive:
  it is a wish of one person, as a device is.
  """

  use Rescord.Resource,
    domain: Rescord.Health,
    shared?: true,
    temporal?: false,
    paper_trail?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  postgres do
    table "health_watchers"

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :watch do
      description "The actor gets an alert when a check fails"
      accept []
      upsert? true
      upsert_identity :one_watcher
      upsert_fields [:user_id]
      change relate_actor(:user)
    end

    destroy :unwatch do
      description "The actor gets no more alerts of the checks"
    end
  end

  # A watch is of one root user: each reads and ends only their own. The
  # alerts read the rows with no actor.
  policies do
    policy action(:watch) do
      authorize_if actor_attribute_equals(:root?, true)
    end

    policy action([:read, :unwatch]) do
      authorize_if expr(user_id == ^actor(:id) and ^actor(:root?) == true)
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :user, Rescord.Accounts.User do
      allow_nil? false
      public? true
      attribute_writable? false
    end
  end

  identities do
    identity :one_watcher, [:user_id]
  end
end
