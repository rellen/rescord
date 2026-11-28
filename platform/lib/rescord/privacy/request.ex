defmodule Rescord.Privacy.Request do
  @moduledoc """
  A request of a person to erase their data in one organisation (ADR 0105,
  GDPR Article 17, APP 11.2 of Australia's Privacy Act). Each erasure
  starts with one, even when an administrator does it at once: the closed
  request is the proof that the organisation did what was asked, and when.

  ## The dates

  A request is due one calendar month after `received_on`, for every
  organisation, whatever its country (`due_on`). A month after 31 January
  is the last day of February. When identity is confirmed later, the
  month starts then. Rescord does not know the holidays of each country,
  so a member moves the day when that matters, with `extend`. An extension
  is at most two more months, with a reason and the day the person was
  told, which must be inside the first month.

  ## The states

  `received`, then `done` (the erasure ran), `refused` (with a reason, such
  as a request that is manifestly unfounded or excessive) or `withdrawn`.
  Only `Rescord.Privacy.erase/3` makes a request `done`.

  ## What it keeps

  `contact` is how to answer the person when that is not the email of the
  account, encrypted with AshCloak, and it goes when the request closes. A
  closed request keeps "Former member N", the dates, the state, what was
  kept and why, and the correlation id of the erasure (ADR 0101), so the
  versions that the erasure wrote can be found. A job deletes it after
  `closed_request_years` of `Rescord.Privacy.Settings`.

  Not temporal and not archived: a delete removes the row. Its paper trail
  redacts the words that a person typed.
  """

  use Rescord.Resource,
    domain: Rescord.Privacy,
    temporal?: false,
    archive?: false,
    extensions: [AshCloak],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Privacy.{Changes, Validations}

  @type t :: %__MODULE__{}

  @ways [:own_page, :email, :letter, :in_person]

  # An erasure of the account, and the pseudonymisation after the months of
  # the settings, write a closed line of their own (ADR 0105).
  @kinds @ways ++ [:account, :automatic]

  postgres do
    table "privacy_requests"

    custom_indexes do
      index [:state]
      index [:user_id]
    end
  end

  cloak do
    # A function, so that AshCloak asks for no vault of the package `cloak`.
    vault(fn _resource, _context -> Rescord.Vault end)
    attributes([:contact])
    encrypt_nil?(false)
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    ignore_attributes [:encrypted_contact]
    sensitive_attributes :redact
  end

  actions do
    defaults [:read]

    read :open do
      description "The requests that wait, the first due first"
      filter expr(state == :received)
      prepare build(sort: [due_on: :asc, received_on: :asc])
    end

    read :closed_before do
      description "The closed requests that closed before an instant. A job runs this"
      argument :before, :utc_datetime_usec, allow_nil?: false
      filter expr(state != :received and closed_at < ^arg(:before))
    end

    create :ask do
      description "The actor asks the organisation to erase their data, from their own page"
      accept []
      change Changes.AskForSelf
      change Changes.DueOn
    end

    create :record do
      description "Records a request that came by email, by letter or in person, for a member or a former member"
      accept [:how_received, :identity, :received_on, :identity_confirmed_on, :contact]
      argument :member_id, :uuid, allow_nil?: false
      validate one_of(:how_received, @ways)
      validate {Rescord.Accounts.Validations.NotAfterToday, attribute: :received_on}
      validate {Rescord.Accounts.Validations.NotAfterToday, attribute: :identity_confirmed_on}
      change Rescord.Accounts.Changes.SetAuthor
      change Changes.ForMember
      change Changes.DueOn
    end

    create :closed do
      description "The closed line of an erasure that no request of the organisation asked for: of the account by a root user, or after the months of the settings"
      accept [:how_received, :identity, :kept, :keep_comments, :former_number, :correlation_id]
      argument :member_id, :uuid, allow_nil?: false
      validate one_of(:how_received, [:account, :automatic])
      change Changes.ForMember
      change set_attribute(:state, :done)
      change set_attribute(:closed_at, &DateTime.utc_now/0)
      change Changes.DueOn
    end

    update :extend do
      description "Moves the day that the request is due, by at most two more months, with a reason"
      require_atomic? false
      accept [:extended_to, :extension_reason, :told_of_extension_on]
      validate attribute_equals(:state, :received)
      validate present([:extended_to, :extension_reason, :told_of_extension_on])
      validate Validations.FitsExtension
    end

    update :refuse do
      description "Refuses the request, with the reason"
      require_atomic? false
      accept [:refusal_reason]
      validate attribute_equals(:state, :received)
      validate present(:refusal_reason), message: "say why"
      change set_attribute(:state, :refused)
      change Changes.Close
    end

    update :withdraw do
      description "The person withdrew the request"
      require_atomic? false
      accept []
      validate attribute_equals(:state, :received)
      change set_attribute(:state, :withdrawn)
      change Changes.Close
    end

    update :complete do
      description "Records the erasure. Only `Rescord.Privacy.erase/3` runs it, and no role has a grant for it"
      require_atomic? false
      accept [:kept, :keep_comments, :correlation_id, :former_number, :told_on]
      validate attribute_equals(:state, :received)
      change set_attribute(:state, :done)
      change Changes.Close
    end

    update :note_told do
      description "Records the day that the person was told of the outcome"
      accept [:told_on]
    end

    destroy :forget do
      description "Deletes a closed request after the years of the settings. A job runs this"
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

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The user whose data the request is about"
    end

    attribute :member_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The member of that user in the organisation, the newest"
    end

    attribute :author_id, :uuid do
      public? true
      writable? false

      description "The user who recorded the request. Empty when the person asked from their own page"
    end

    # AshCloak takes this attribute away, and makes the attribute
    # `encrypted_contact` and the calculation `contact`.
    attribute :contact, :string do
      sensitive? true
      constraints max_length: 500
    end

    attribute :how_received, :atom do
      allow_nil? false
      default :own_page
      public? true
      constraints one_of: @kinds
    end

    attribute :identity, :string do
      public? true
      sensitive? true
      constraints max_length: 300

      description "How the person who recorded the request checked who asked. \"Signed in\" from the own page"
    end

    attribute :received_on, :date do
      allow_nil? false
      public? true
      description "The day that the request arrived"
    end

    attribute :identity_confirmed_on, :date do
      public? true
      description "The day that the identity was confirmed, when that came after the request"
    end

    attribute :due_on, :date do
      allow_nil? false
      public? true
      writable? false
      description "One calendar month after the request, or after the identity was confirmed"
    end

    attribute :extended_to, :date do
      public? true
      description "The day that the request is due after an extension"
    end

    attribute :extension_reason, :string do
      public? true
      sensitive? true
      constraints max_length: 1_000
    end

    attribute :told_of_extension_on, :date do
      public? true
    end

    attribute :state, :atom do
      allow_nil? false
      default :received
      public? true
      writable? false
      constraints one_of: [:received, :done, :refused, :withdrawn]
    end

    attribute :refusal_reason, :string do
      public? true
      sensitive? true
      constraints max_length: 2_000
    end

    attribute :kept, :string do
      public? true
      constraints max_length: 4_000

      description "What the erasure kept, and why: the holds of the money records and the reasons that a member added"
    end

    attribute :keep_comments, :boolean do
      public? true
      description "Whether the erasure kept the comments of the person, signed Former member N"
    end

    attribute :former_number, :integer do
      public? true
      description "The number of Former member N, after the erasure"
    end

    attribute :correlation_id, :uuid do
      public? true
      description "The correlation id of the versions that the erasure wrote (ADR 0101)"
    end

    attribute :told_on, :date do
      public? true
      description "The day that the person was told of the outcome"
    end

    attribute :closed_at, :utc_datetime_usec do
      public? true
      writable? false
    end

    create_timestamp :inserted_at
  end

  calculations do
    calculate :due, :date, expr(extended_to || due_on) do
      public? true
      description "The day that the request is due, after any extension"
    end
  end
end
