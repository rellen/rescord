defmodule Rescord.Ruby.Provider do
  @moduledoc """
  A provider of a language model that this server can use for Ruby: the
  service, the model, the address, the limits, the prices and the key
  (ADR 0069). A root user sets it on the page `/root/ruby`. No setting of
  a provider is in the environment or in the application config (ADR 0068).

  The key is encrypted with AshCloak in `Rescord.Vault`. The attribute
  `api_key` is an argument of the actions `add` and `set_key`, and a
  calculation that only `Rescord.Ruby.LLM` loads. The column holds the
  encrypted form. `key_hint` and `key_set_at` are in the clear, so that a
  page says "ends in 3f9k, set on 3 March" and decrypts nothing.

  The resource is in the shared schema, and it is not temporal: a history
  row would keep each old key. Its paper trail leaves the encrypted
  attribute out, so a version says that a key was set, and holds nothing of
  it. To remove a provider empties the key and archives the row.

  Only a root user reads or changes a provider. The actor of Ruby is never
  one, so no tool reaches it.
  """

  use Rescord.Resource,
    domain: Rescord.Ruby,
    shared?: true,
    temporal?: false,
    extensions: [AshCloak],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Ruby.{Changes, Reason, Validations}
  alias Rescord.Ruby.LLM.Profile

  @type t :: %__MODULE__{}

  postgres do
    table "ruby_providers"
  end

  cloak do
    # A function, so that AshCloak asks for no vault of the package `cloak`.
    vault(fn _resource, _context -> Rescord.Vault end)
    attributes([:api_key])
    # A provider with no key has NULL in the column.
    encrypt_nil?(false)
    on_decrypt({__MODULE__, :may_decrypt, []})
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    # Without this line a version holds the encrypted key.
    ignore_attributes [:encrypted_api_key]
  end

  actions do
    defaults [:read]

    create :add do
      accept [
        :name,
        :kind,
        :model,
        :base_url,
        :region,
        :api_key,
        :effort,
        :max_output_tokens,
        :context_tokens,
        :price_input,
        :price_output,
        :default_allowance
      ]

      change Changes.KindDefaults
      change Changes.NoteKey
      validate Validations.ProviderFits
    end

    # Each field but the kind and the key. The kind decides which fields a
    # provider has, so it stays. A form that sent an empty key to an action
    # that takes it would empty the key.
    update :change do
      require_atomic? false

      accept [
        :name,
        :model,
        :base_url,
        :region,
        :effort,
        :max_output_tokens,
        :context_tokens,
        :price_input,
        :price_output,
        :default_allowance,
        :offered
      ]

      validate Validations.ProviderFits
      # The last test says what the saved model at the saved address
      # answered. After a change of one of them, nobody tested the provider.
      change Changes.ForgetTest
    end

    # The key has an action of its own, so that its version says `set_key`,
    # with the new hint and nothing else.
    update :set_key do
      require_atomic? false
      accept [:api_key]
      # Without this, an empty text empties the key and keeps the old hint.
      validate present(:api_key), message: "type the key"
      change Changes.NoteKey
      # The rule for a key over plain HTTP needs the key and the address.
      validate Validations.ProviderFits
      # A new key is a key that nobody tested.
      change set_attribute(:tested_at, nil)
      change set_attribute(:test_result, nil)
    end

    update :note_test do
      description "Writes what \"Test\" found. Only `Rescord.Ruby.test_provider/2` runs it"
      accept [:tested_at, :test_result]
    end

    # AshArchival keeps the row, and this empties its key.
    destroy :remove do
      require_atomic? false
      change fn changeset, _context -> AshCloak.encrypt_and_set(changeset, :api_key, nil) end
      # `Profile.problems/1` reads `key_set_at` as "a key is stored".
      change set_attribute(:key_set_at, nil)
      change set_attribute(:key_hint, nil)
      change set_attribute(:offered, false)
    end
  end

  # Only a root user. A read by another actor gives an empty list, and a
  # write is refused. The domain reads a provider for a person who is no
  # root user, with the fields that such a person may see, after its own
  # check.
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

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100
      description "The name that an administrator of an organisation reads"
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: Profile.kinds()
      description "The service that runs the model"
    end

    attribute :model, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
      description "The model, by the name that the service gives it"
    end

    attribute :base_url, :string do
      public? true
      constraints max_length: 500
      description "The address of the model, for a service that has no fixed one"
    end

    attribute :region, :string do
      public? true
      constraints max_length: 64
      description "The region of Amazon Bedrock that a request goes to"
    end

    # AshCloak takes this attribute away, and makes the attribute
    # `encrypted_api_key` and the calculation `api_key`. It is not public.
    attribute :api_key, :string do
      sensitive? true
      constraints max_length: 2_000
    end

    attribute :key_hint, :string do
      public? true
      description "The last four characters of the key, in the clear"
    end

    attribute :key_set_at, :utc_datetime_usec do
      public? true
      description "When the key was set. A row with a key has a time here"
    end

    attribute :effort, :atom do
      allow_nil? false
      default :low
      public? true
      constraints one_of: [:low, :medium, :high]
      description "How much a model of Claude thinks before it answers"
    end

    attribute :max_output_tokens, :integer do
      allow_nil? false
      default 4_096
      public? true
      description "The most tokens of one answer, with its thinking"
    end

    attribute :context_tokens, :integer do
      public? true
      description "The most tokens of one request"
    end

    attribute :price_input, :integer do
      public? true
      constraints min: 0, max: 1_000_000_000

      description "Millionths of a US dollar for a million tokens of input, for a model with no price in Rescord"
    end

    attribute :price_output, :integer do
      public? true
      constraints min: 0, max: 1_000_000_000

      description "Millionths of a US dollar for a million tokens of output, for a model with no price in Rescord"
    end

    attribute :default_allowance, :integer do
      allow_nil? false
      default 2_000
      public? true
      constraints min: 0, max: 10_000_000
      description "Whole US cents for a month, which an organisation starts with"
    end

    attribute :offered, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether an administrator of an organisation can choose this provider"
    end

    attribute :tested_at, :utc_datetime_usec do
      public? true
      description "When \"Test\" ran last"
    end

    attribute :test_result, :atom do
      public? true
      constraints one_of: [:ok | Reason.all()]
      description "What the last test found: `ok`, or the reason of the failure"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  @doc """
  AshCloak asks this before each decryption. Only a call with the mark
  passes, and `Rescord.Ruby.LLM` is the one module that writes the mark.
  The mark stops an accident, such as a page that loads each calculation.
  It is no lock against code: the policy guards the record.
  """
  def may_decrypt(_resource, _records, _field, %{source_context: %{rescord_vault: :open}}),
    do: :ok

  def may_decrypt(_resource, _records, field, _context),
    do: {:error, Rescord.Vault.Sealed.exception(field: field)}
end
