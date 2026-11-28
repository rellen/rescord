defmodule Rescord.Notifications.PushSubscription do
  @moduledoc """
  A device of one person that gets their notifications through Web Push
  (issue 29, ADR 0106): the address of the device at its push service, its
  public key, and its secret `auth`, encrypted with AshCloak in
  `Rescord.Vault`. Together they let the server encrypt a message that only
  the device reads (RFC 8291).

  A device belongs to the user, not to an organisation: it gets the
  notifications of each organisation of the user. So the resource is in
  the shared schema, and its policy is the person, as for a user.

  `subscribe` takes only an address at a push service of a browser
  (`Rescord.Notifications.WebPush.allowed_endpoint?/1`): the server sends a
  request to it. The same address subscribes once (an upsert). A push
  service that answers that the device is gone ends it (`forget`).
  """

  use Rescord.Resource,
    domain: Rescord.Notifications,
    shared?: true,
    temporal?: false,
    archive?: false,
    paper_trail?: false,
    extensions: [AshCloak],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Notifications.{Changes, Validations}

  @type t :: %__MODULE__{}

  @devices [:iphone, :ipad, :android, :mac, :windows, :linux, :other]

  postgres do
    table "push_subscriptions"

    references do
      reference :user, on_delete: :delete
    end
  end

  cloak do
    vault(fn _resource, _context -> Rescord.Vault end)
    attributes([:auth])
    encrypt_nil?(false)
    on_decrypt({Rescord.Notifications.Settings, :may_decrypt, []})
  end

  actions do
    defaults [:read]

    create :subscribe do
      description "The actor gets their notifications on this device"
      accept [:endpoint, :device_key, :auth, :device]
      upsert? true
      upsert_identity :one_endpoint
      upsert_fields [:user_id, :device_key, :encrypted_auth, :device]
      change Changes.SetUser
      validate Validations.Device
    end

    destroy :remove do
      description "The actor takes a device of their own off"
    end

    destroy :forget do
      description "The push service says that the device is gone. Only the channel runs it"
    end

    destroy :forget_all do
      description "Each device goes with the old keys of the server. Only `make_keys` runs it"
    end

    update :note_sent do
      description "When the server last sent to the device. Only the channel runs it"
      accept []
      change set_attribute(:last_sent_at, &DateTime.utc_now/0)
    end
  end

  # A device is of one person: no bypass for a root user. The channel and
  # the domain run their actions with no actor.
  policies do
    policy action([:read, :remove]) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action(:subscribe) do
      authorize_if actor_present()
    end

    policy action([:forget, :forget_all, :note_sent]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :endpoint, :string do
      allow_nil? false
      sensitive? true
      constraints max_length: 1_000
      description "The address of the device at its push service"
    end

    attribute :device_key, :string do
      allow_nil? false
      sensitive? true
      constraints max_length: 200
      description "The public key of the device, as Base64url (p256dh)"
    end

    # AshCloak takes this attribute away, and makes `encrypted_auth`.
    attribute :auth, :string do
      sensitive? true
      constraints max_length: 100
    end

    attribute :device, :atom do
      allow_nil? false
      default :other
      public? true
      constraints one_of: @devices
      description "The kind of device, which the browser says, for the list of a person"
    end

    attribute :last_sent_at, :utc_datetime_usec do
      public? true
      writable? false
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
    identity :one_endpoint, [:endpoint]
  end

  @doc "The kinds of device that a page can name."
  @spec devices() :: [atom]
  def devices, do: @devices
end
