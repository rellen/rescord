defmodule Rescord.Notifications.NtfyTopic do
  @moduledoc """
  The topic of ntfy of one person (issue 29, ADR 0106): a random name of 32
  characters, at the server of ntfy of `Rescord.Notifications.Settings`. The
  person subscribes to it in the app of ntfy.

  A topic of ntfy is open to each person who knows its name, so the name is
  the secret: it is encrypted with AshCloak in `Rescord.Vault`, only its
  person reads it (`Rescord.Notifications.ntfy_address/1`), and `renew`
  makes a new name, which ends the old one. A message holds a pointer only.

  A topic belongs to the user, as a device of Web Push does: it is in the
  shared schema, and gets the notifications of each organisation of the
  user.
  """

  use Rescord.Resource,
    domain: Rescord.Notifications,
    shared?: true,
    temporal?: false,
    archive?: false,
    paper_trail?: false,
    extensions: [AshCloak],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Notifications.Changes

  @type t :: %__MODULE__{}

  postgres do
    table "ntfy_topics"

    references do
      reference :user, on_delete: :delete
    end
  end

  cloak do
    vault(fn _resource, _context -> Rescord.Vault end)
    attributes([:topic])
    encrypt_nil?(false)
    on_decrypt({Rescord.Notifications.Settings, :may_decrypt, []})
  end

  actions do
    defaults [:read]

    create :start do
      description "The actor gets a topic of their own"
      accept []
      upsert? true
      upsert_identity :one_topic
      upsert_fields [:encrypted_topic, :inserted_at]
      change Changes.SetUser
      change Changes.NewTopic
    end

    update :renew do
      description "A new name for the topic of the actor. The old one stops"
      require_atomic? false
      accept []
      change Changes.NewTopic
    end

    destroy :stop do
      description "The actor gets nothing on ntfy any more"
    end
  end

  policies do
    policy action([:read, :renew, :stop]) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action(:start) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end

    # AshCloak takes this attribute away, and makes `encrypted_topic`.
    attribute :topic, :string do
      sensitive? true
      constraints max_length: 64
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :user, Rescord.Accounts.User do
      allow_nil? false
      define_attribute? false
      source_attribute :user_id
    end
  end

  identities do
    identity :one_topic, [:user_id]
  end
end
