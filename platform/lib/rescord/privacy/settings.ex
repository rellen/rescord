defmodule Rescord.Privacy.Settings do
  @moduledoc """
  How long an organisation keeps what names a person, and what its privacy
  notice says (ADR 0105). One row in the schema of the organisation. With
  no row, each setting has its start value.

    * `money_years` - how long an expense keeps the email of a person who
      was erased, after the day of the expense. 7 at the start: the longest
      of the Australian periods (5 years for tax records, 7 for a charity
      of the ACNC). An organisation elsewhere sets its own.
    * `pseudonymise_after_months` - when set, a daily job pseudonymises
      each former member who left longer ago, with no request. Empty at
      the start: never.
    * `closed_request_years` - how long a closed request stays, as the
      proof that the organisation did what was asked. 3 at the start.
    * `contact_name`, `contact_email`, `authority` and `notice_text` - the
      blanks of the privacy notice. The notice is public, so none of them
      is a secret.

  It holds no secret, so it needs no AshCloak, and it is never an
  environment variable: nothing in it is needed before the first sign-in.
  The power `privacy` reads and changes it.
  """

  use Rescord.Resource,
    domain: Rescord.Privacy,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  @fields [
    :money_years,
    :pseudonymise_after_months,
    :closed_request_years,
    :contact_name,
    :contact_email,
    :authority,
    :notice_text
  ]

  postgres do
    table "privacy_settings"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :set do
      description "The first settings of privacy of the organisation"
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

    policy always() do
      authorize_if Rescord.Accounts.Checks.Granted
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

    attribute :money_years, :integer do
      allow_nil? false
      default 7
      public? true
      constraints min: 1, max: 30
      description "The years that an expense keeps the email of a person who was erased"
    end

    attribute :pseudonymise_after_months, :integer do
      public? true
      constraints min: 1, max: 600

      description "The months after which a former member is pseudonymised with no request. Empty: never"
    end

    attribute :closed_request_years, :integer do
      allow_nil? false
      default 3
      public? true
      constraints min: 1, max: 30
      description "The years that a closed request stays"
    end

    attribute :contact_name, :string do
      public? true
      constraints max_length: 120
      description "Who answers a question about privacy, for the notice"
    end

    attribute :contact_email, :ci_string do
      public? true
      constraints max_length: 254
      description "Where a person writes about privacy, for the notice"
    end

    attribute :authority, :string do
      public? true
      constraints max_length: 200
      description "The authority that a person can complain to, for the notice"
    end

    attribute :notice_text, :string do
      public? true
      constraints max_length: 5_000
      description "The paragraphs of the organisation's own that the notice adds at its end"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :one_row, [:which]
  end
end
