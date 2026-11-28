defmodule Rescord.Privacy.InstanceSettings do
  @moduledoc """
  What the privacy notices of the server say about the server itself
  (ADR 0105): who runs it, where its servers and files are, which mail
  provider sends its email, and how many days its backups keep a dump.
  One row in the shared schema, which a root user keeps. With no row, each
  blank is missing and the notices say so.

  Rescord cannot know these: the operator types them. The days of the
  backups are `RESCORD_BACKUP_KEEP_DAYS` of the backup service, which runs
  apart from Rescord, so the operator types the same number here.

  It holds no secret, so it needs no AshCloak, and it is never an
  environment variable: nothing in it is needed before the first sign-in.
  """

  use Rescord.Resource,
    domain: Rescord.Privacy,
    shared?: true,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  @fields [:operator_name, :operator_contact, :hosting, :mail_provider, :backup_days]

  postgres do
    table "privacy_instance_settings"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :set do
      description "The first settings of privacy of the server"
      accept @fields
    end

    update :change do
      accept @fields
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    # Each person reads it: the notices are public.
    policy action_type(:read) do
      authorize_if always()
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

    attribute :operator_name, :string do
      public? true
      constraints max_length: 200
      description "Who runs this server, for the notices"
    end

    attribute :operator_contact, :string do
      public? true
      constraints max_length: 254
      description "Where a person writes to the operator about their account"
    end

    attribute :hosting, :string do
      public? true
      constraints max_length: 200
      description "Where the servers and the files are: the country and the provider"
    end

    attribute :mail_provider, :string do
      public? true
      constraints max_length: 200
      description "The provider that sends the email of the server"
    end

    attribute :backup_days, :integer do
      allow_nil? false
      default 14
      public? true
      constraints min: 1, max: 3_650

      description "The days that a backup keeps a dump: RESCORD_BACKUP_KEEP_DAYS of the backup service"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :one_row, [:which]
  end
end
