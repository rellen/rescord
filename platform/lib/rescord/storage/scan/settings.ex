defmodule Rescord.Storage.Scan.Settings do
  @moduledoc """
  The virus scan of the PDFs (issue 37, ADR 0113): one row for the server,
  which a root user sets on the page `/root/scan`. No setting of it is in
  the environment or in the application config (ADR 0068).

  `scan_on` turns the scan on, and `address` says where clamd listens:
  `host:port`, or the absolute path of a Unix socket. clamd takes no
  password, so the row holds no secret. A field with a secret would be an
  attribute of AshCloak, as the token of ntfy is
  (`Rescord.Notifications.Settings`).

  With no row, or with the scan off, no PDF is scanned. Only a root user
  reads or changes the row; the domain reads it with no actor for a scan.
  """

  use Rescord.Resource,
    domain: Rescord.Storage.Scan,
    shared?: true,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  postgres do
    table "scan_settings"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :set do
      description "The first settings of the scan of the server"
      accept [:scan_on, :address]
      validate Rescord.Storage.Scan.Validations.SettingsFit
    end

    update :change do
      require_atomic? false
      accept [:scan_on, :address]
      validate Rescord.Storage.Scan.Validations.SettingsFit
    end
  end

  # Only a root user. The domain reads the row with no actor for a scan.
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

    attribute :scan_on, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether each PDF goes to clamd before Rescord keeps it"
    end

    attribute :address, :string do
      public? true
      constraints max_length: 300, trim?: true
      description "Where clamd listens: host:port, or the absolute path of a Unix socket"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :one_row, [:which]
  end
end
