defmodule Rescord.Notifications.Settings do
  @moduledoc """
  How this server sends notifications outside the app (issue 29,
  ADR 0106): one row for the server, which a root user sets on the page
  `/root/push`. No setting of it is in the environment or in the
  application config (ADR 0068).

  **Web Push.** The key pair of the server (VAPID, RFC 8292): a push
  service delivers a message of this server only with a signature of the
  private key, and a browser subscribes with the public key. The private
  key is encrypted with AshCloak in `Rescord.Vault`. `make_keys` makes a
  new pair; `Rescord.Notifications.make_keys/1` also ends each subscription
  of a device, which the old key made. `contact` is the address that a push
  service can write to, `mailto:` or `https://`.

  **ntfy.** The address of a server of ntfy (`https://ntfy.sh`, or one that
  the operator runs), and an access token for a server that asks for one,
  encrypted too.

  Each channel is off until a root user turns it on. Only a root user reads
  or changes the row; the domain reads it with no actor for a job.
  """

  use Rescord.Resource,
    domain: Rescord.Notifications,
    shared?: true,
    temporal?: false,
    archive?: false,
    extensions: [AshCloak],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Notifications.Changes

  @type t :: %__MODULE__{}

  postgres do
    table "notification_settings"
  end

  cloak do
    # A function, so that AshCloak asks for no vault of the package `cloak`.
    vault(fn _resource, _context -> Rescord.Vault end)
    attributes([:vapid_private_key, :ntfy_token])
    encrypt_nil?(false)
    on_decrypt({__MODULE__, :may_decrypt, []})
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    # Without this line a version holds the encrypted secrets.
    ignore_attributes [:encrypted_vapid_private_key, :encrypted_ntfy_token]
  end

  actions do
    defaults [:read]

    create :start do
      description "The row of the server, at the first save of a root user"
      accept []
    end

    update :change do
      require_atomic? false
      accept [:contact, :push_on, :ntfy_url, :ntfy_on]
      validate Rescord.Notifications.Validations.SettingsFit
    end

    update :make_keys do
      description "A new key pair of Web Push. Each subscription of a device ends with it"
      require_atomic? false
      accept []
      change Changes.MakeKeys
    end

    # The token has an action of its own: an empty text in a form of the
    # other fields would empty it.
    update :set_ntfy_token do
      require_atomic? false
      accept [:ntfy_token]
      validate present(:ntfy_token), message: "type the token"
      change set_attribute(:ntfy_token_set_at, &DateTime.utc_now/0)
    end

    update :forget_ntfy_token do
      require_atomic? false
      change fn changeset, _context -> AshCloak.encrypt_and_set(changeset, :ntfy_token, nil) end
      change set_attribute(:ntfy_token_set_at, nil)
    end
  end

  # Only a root user. The domain reads the row with no actor for a job.
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

    # Each row has the same value here, so the identity allows one row.
    attribute :which, :atom do
      allow_nil? false
      default :settings
      writable? false
      constraints one_of: [:settings]
    end

    attribute :push_on, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether the server sends notifications to devices with Web Push"
    end

    attribute :contact, :string do
      public? true
      constraints max_length: 300, trim?: true
      description "The address for the push services: mailto: or https://"
    end

    attribute :vapid_public_key, :string do
      public? true
      writable? false
      description "The public key of Web Push, as Base64url. A browser subscribes with it"
    end

    # AshCloak takes this attribute away, and makes `encrypted_vapid_private_key`.
    attribute :vapid_private_key, :string do
      sensitive? true
    end

    attribute :keys_made_at, :utc_datetime_usec do
      public? true
      writable? false
    end

    attribute :ntfy_on, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether the server sends notifications to topics of ntfy"
    end

    attribute :ntfy_url, :string do
      public? true
      constraints max_length: 300, trim?: true
      description "The address of the server of ntfy, such as https://ntfy.sh"
    end

    attribute :ntfy_token, :string do
      sensitive? true
      constraints max_length: 500
    end

    attribute :ntfy_token_set_at, :utc_datetime_usec do
      public? true
      writable? false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :one_row, [:which]
  end

  @doc """
  AshCloak asks this before each decryption. Only a call with the mark
  passes, and the channels of `Rescord.Notifications` are the modules that
  write it.
  """
  def may_decrypt(_resource, _records, _field, %{source_context: %{rescord_vault: :open}}),
    do: :ok

  def may_decrypt(_resource, _records, field, _context),
    do: {:error, Rescord.Vault.Sealed.exception(field: field)}
end
