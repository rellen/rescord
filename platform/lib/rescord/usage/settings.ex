defmodule Rescord.Usage.Settings do
  @moduledoc """
  What the server does with its usage counts (ADR 0098): one row for the
  whole server, which a root user sets on the page `/root/usage`. No
  setting of it is in the environment or in the application config
  (ADR 0068). A server with no row counts on the server and sends nothing:
  the mode `local`.

  - `mode`: `off` counts nothing, `local` counts and keeps the counts on
    the server, `send` also sends each full day to `endpoint`.
  - `format`: `otlp`, the metrics of OpenTelemetry as JSON over HTTP, or
    `json`, the plain document of Rescord (`Rescord.Usage.Document`).
  - `token`: sent as `authorization: Bearer`, encrypted with AshCloak in
    `Rescord.Vault`. `token_hint` and `token_set_at` are in the clear, so
    that the page says "ends in 3f9k" and decrypts nothing. Only
    `Rescord.Usage.Sender` decrypts it.
  - `installation_id`: a random id that a receiver needs to put the days of
    one server together. It comes from nothing of the server, and a root
    user can make a new one.
  - `sending_since`: the day that a root user turned the mode `send` on.
    No day before it is ever sent.

  In the shared schema, not temporal: a history row would keep each old
  token. Its paper trail leaves the encrypted token out, and the notes of
  each send and each test, which say nothing that a person did.
  """

  use Rescord.Resource,
    domain: Rescord.Usage,
    shared?: true,
    temporal?: false,
    archive?: false,
    extensions: [AshCloak],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Usage.Changes

  @type t :: %__MODULE__{}

  @results [:ok, :status, :unreachable, :sealed]

  postgres do
    table "usage_settings"
  end

  cloak do
    # A function, so that AshCloak asks for no vault of the package `cloak`.
    vault(fn _resource, _context -> Rescord.Vault end)
    attributes([:token])
    encrypt_nil?(false)
    on_decrypt({__MODULE__, :may_decrypt, []})
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    # Without this line a version holds the encrypted token.
    ignore_attributes [:encrypted_token]
    # A send and a test write what they found, each hour: no person did it.
    ignore_actions [:note_send, :note_test]
  end

  actions do
    defaults [:read]

    create :start do
      description "The row of the server, at the first save of a root user"
      accept []
    end

    update :change do
      require_atomic? false
      accept [:mode, :format, :endpoint]
      change Changes.SendingSince
      validate Changes.EndpointFits
    end

    # The token has an action of its own, so that its version says
    # `set_token`, with the new hint and nothing else.
    update :set_token do
      require_atomic? false
      accept [:token]
      # Without this, an empty text empties the token and keeps the old hint.
      validate present(:token), message: "type the token"
      change Changes.NoteToken
      validate Changes.EndpointFits
    end

    update :forget_token do
      require_atomic? false
      change fn changeset, _context -> AshCloak.encrypt_and_set(changeset, :token, nil) end
      change set_attribute(:token_hint, nil)
      change set_attribute(:token_set_at, nil)
    end

    update :new_installation do
      description "A new random id: a receiver cannot tie what comes next to what came before"
      change set_attribute(:installation_id, &Ash.UUID.generate/0)
    end

    update :note_send do
      description "Writes what a send found. Only the domain runs it"
      accept [:last_sent_day, :last_attempt_at, :last_result, :last_status]
    end

    update :note_test do
      description "Writes what \"Send a test\" found. Only the domain runs it"
      accept [:tested_at, :test_result, :test_status]
    end
  end

  # Only a root user. The domain writes the notes of a send with no actor.
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

    attribute :mode, :atom do
      allow_nil? false
      default :local
      public? true
      constraints one_of: [:off, :local, :send]
      description "Count nothing, count on the server, or count and send"
    end

    attribute :format, :atom do
      allow_nil? false
      default :otlp
      public? true
      constraints one_of: [:otlp, :json]
      description "The metrics of OpenTelemetry as JSON (OTLP), or the plain document of Rescord"
    end

    attribute :endpoint, :string do
      public? true
      constraints max_length: 500
      description "The address that gets the counts of each full day, with POST"
    end

    # AshCloak takes this attribute away, and makes the attribute
    # `encrypted_token` and the calculation `token`. It is not public.
    attribute :token, :string do
      sensitive? true
      constraints max_length: 2_000
    end

    attribute :token_hint, :string do
      public? true
      description "The last four characters of the token, in the clear"
    end

    attribute :token_set_at, :utc_datetime_usec do
      public? true
      description "When the token was set. A row with a token has a time here"
    end

    attribute :installation_id, :uuid do
      allow_nil? false
      default &Ash.UUID.generate/0
      public? true
      writable? false
      description "A random id of this server, from nothing of the server"
    end

    attribute :sending_since, :date do
      public? true
      writable? false
      description "The day that the mode send was turned on. No day before it is sent"
    end

    attribute :last_sent_day, :date do
      public? true
      description "The newest full day that the address took, or that had no count"
    end

    attribute :last_attempt_at, :utc_datetime_usec do
      public? true
      description "When Rescord sent last"
    end

    attribute :last_result, :atom do
      public? true
      constraints one_of: @results
      description "What the last send found"
    end

    attribute :last_status, :integer do
      public? true
      description "The HTTP status of the last answer"
    end

    attribute :tested_at, :utc_datetime_usec do
      public? true
      description "When \"Send a test\" ran last"
    end

    attribute :test_result, :atom do
      public? true
      constraints one_of: @results
    end

    attribute :test_status, :integer do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :one_row, [:which]
  end

  @doc "What a send or a test can find."
  @spec results() :: [atom]
  def results, do: @results

  @doc """
  AshCloak asks this before each decryption. Only a call with the mark
  passes, and `Rescord.Usage.Sender` is the one module that writes it.
  """
  def may_decrypt(_resource, _records, _field, %{source_context: %{rescord_vault: :open}}),
    do: :ok

  def may_decrypt(_resource, _records, field, _context),
    do: {:error, Rescord.Vault.Sealed.exception(field: field)}
end
