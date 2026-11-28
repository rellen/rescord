defmodule Rescord.Expenses.Expense do
  @moduledoc """
  Something that a member or the organisation paid for (ADR 0082): a
  bill of a vet, a bag of food, the fuel of a trip.

  An expense says who paid (`Rescord.Expenses.PaidBy`), the amount, the
  date of the payment, who was paid, what it was for, a category of the list
  of the organisation, and the resident that it was for when there is one.
  Its files are its receipts (`Rescord.Expenses.Receipt`).

  Rescord is not an accounting system. An expense is a record for the people
  of the organisation, and for the export to the system that does the
  accounts: nothing here is a ledger, and Rescord pays nobody.

  ## The amount

  The amount is money: a decimal with its currency (`AshMoney.Types.Money`).
  No action takes the currency. A new expense is in the currency of the
  organisation, and an expense keeps its currency afterwards.
  `Rescord.Expenses.Changes.SetAmount` makes the amount from the number of
  the argument `amount`: more than zero, with no more decimal places than
  the currency has.

  ## States

      submitted --approve--> approved --reimburse--> reimbursed
      submitted --decline--> declined --revise--> submitted
      approved, declined, reimbursed --reopen--> submitted

  A new expense waits for a decision: it is `submitted`. `record` is the one
  exception: an expense that the organisation paid, recorded by a person who
  can approve, is approved at once. `reimburse` is for an expense that a
  member paid: the organisation paid the member back. A person withdraws an
  expense that waits or that was declined: the row and its history stay.

  AshStateMachine holds the states, so this resource is not temporal
  (ADR 0012). Its history is in its paper trail.

  ## Two people at the same time

  The state machine reads the state of the record that the caller has in
  hand, which can be old. Each action that changes the state also has a
  filter on the state in the database, as a task has. When a second person
  decides an expense that a first person decided a moment before, the second
  action returns `Ash.Error.Changes.StaleRecord`.

  No action takes as input the number, the state, the author, the person who
  decided or the person who paid the member back.
  """

  use Rescord.Resource,
    domain: Rescord.Expenses,
    temporal?: false,
    extensions: [AshStateMachine],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Expenses.{Changes, Validations}

  postgres do
    table "expenses"

    # The number counts up in the schema of the organisation.
    migration_types number: :bigserial

    # A page reads the expenses of a period, of a state, of a person and of
    # a resident.
    custom_indexes do
      index [:incurred_on]
      index [:state]
      index [:payer_id]
      index [:resident_id]
    end
  end

  state_machine do
    initial_states [:submitted, :approved]
    default_initial_state :submitted

    transitions do
      transition :revise, from: [:submitted, :declined], to: :submitted
      transition :approve, from: :submitted, to: :approved
      transition :decline, from: :submitted, to: :declined
      transition :reimburse, from: :approved, to: :reimbursed
      transition :reopen, from: [:approved, :declined, :reimbursed], to: :submitted
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :submit do
      description "Records an expense that the actor or the organisation paid. It waits for a decision"
      accept [:paid_by, :incurred_on, :payee, :description, :category_id, :resident_id, :note]
      argument :amount, :decimal, allow_nil?: false
      change Changes.SetAuthor
      change Changes.SetAmount
      change Changes.SetPayer
      validate {Validations.NotAfterToday, attribute: :incurred_on}
      validate Validations.CategoryOfOrganisation, before_action?: true
      validate Validations.ResidentOfOrganisation, before_action?: true
    end

    create :record do
      description "Records an expense as a person who manages the expenses: one that another member paid, or one that the organisation paid, which is approved at once"

      accept [:paid_by, :incurred_on, :payee, :description, :category_id, :resident_id, :note]
      argument :amount, :decimal, allow_nil?: false
      argument :payer_id, :uuid
      change Changes.SetAuthor
      change Changes.SetAmount
      change Changes.SetPayer
      change Changes.ApproveWhatTheOrganisationPaid
      validate {Validations.NotAfterToday, attribute: :incurred_on}
      validate Validations.CategoryOfOrganisation, before_action?: true
      validate Validations.ResidentOfOrganisation, before_action?: true
      validate Validations.PayerIsMember, before_action?: true
    end

    update :revise do
      description "Changes an expense that waits for a decision or that was declined. It waits for a decision again"
      accept [:incurred_on, :payee, :description, :category_id, :resident_id, :note]
      argument :amount, :decimal
      require_atomic? false
      change filter(expr(state in [:submitted, :declined]))
      change transition_state(:submitted)
      change Changes.SetAmount
      change Changes.ClearDecision
      validate {Validations.NotAfterToday, attribute: :incurred_on}
      validate Validations.CategoryOfOrganisation, before_action?: true
      validate Validations.ResidentOfOrganisation, before_action?: true
    end

    update :approve do
      description "Approves an expense that waits for a decision"
      accept []
      require_atomic? false
      change filter(expr(state == :submitted))
      change transition_state(:approved)
      change Changes.Decide
    end

    update :decline do
      description "Declines an expense that waits for a decision, with the reason"
      accept [:decline_reason]
      require_atomic? false
      validate present(:decline_reason), message: "is required to decline an expense"
      change filter(expr(state == :submitted))
      change transition_state(:declined)
      change Changes.Decide
    end

    update :reimburse do
      description "Records that the organisation paid the member back"
      accept [:reimbursed_on, :reimbursement_reference]
      require_atomic? false
      change filter(expr(state == :approved and paid_by == :member))
      change transition_state(:reimbursed)
      change Changes.PayBack
      validate {Validations.NotAfterToday, attribute: :reimbursed_on}
    end

    update :reopen do
      description "Opens the decision again: the expense waits for a decision, with no decision and no payment"
      accept []
      require_atomic? false
      change filter(expr(state in [:approved, :declined, :reimbursed]))
      change transition_state(:submitted)
      change Changes.ClearDecision
    end

    destroy :withdraw do
      description "Withdraws an expense that waits for a decision or that was declined. The row and its history stay"
      require_atomic? false

      validate attribute_in(:state, [:submitted, :declined]),
        message: "is decided: only an expense that waits or that was declined can be withdrawn"

      change Changes.TakeOffReceipts
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

    attribute :number, :integer do
      allow_nil? false
      generated? true
      public? true
      writable? false

      description "A number that counts up in the organisation. A person writes it on a bank transfer"
    end

    attribute :paid_by, Rescord.Expenses.PaidBy do
      allow_nil? false
      public? true
    end

    attribute :amount, AshMoney.Types.Money do
      allow_nil? false
      public? true
      writable? false

      description "The whole amount, with its tax, in the currency of the organisation at the time of the record"
    end

    attribute :incurred_on, :date do
      allow_nil? false
      public? true
      description "The date of the payment, not after today in the organisation"
    end

    attribute :payee, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 120
      description "Who was paid: a shop, a clinic, a person"
    end

    attribute :description, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200
      description "What the expense was for"
    end

    attribute :note, :string do
      public? true
      constraints max_length: 1000
    end

    # The ids below name records of temporal resources, and of the users. The
    # database can hold no key from a table with no period to one with a
    # period, so each is a plain id.
    attribute :category_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :resident_id, :uuid do
      public? true
      description "The resident that the expense was for, or none"
    end

    attribute :payer_id, :uuid do
      public? true
      writable? false
      description "The user who paid, when a member paid. The organisation pays this person back"
    end

    attribute :author_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The user who recorded the expense"
    end

    attribute :decided_by_id, :uuid do
      public? true
      writable? false
    end

    attribute :decided_at, :utc_datetime_usec do
      public? true
      writable? false
    end

    attribute :decline_reason, :string do
      public? true
      constraints max_length: 500
    end

    attribute :reimbursed_on, :date do
      public? true
      description "The date on which the organisation paid the member back"
    end

    attribute :reimbursed_by_id, :uuid do
      public? true
      writable? false
    end

    attribute :reimbursement_reference, :string do
      public? true
      constraints max_length: 120
      description "What finds the payment again, for example the words of the bank transfer"
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    has_many :receipts, Rescord.Expenses.Receipt do
      public? true
    end

    belongs_to :category, Rescord.Lists.ExpenseCategory do
      public? true
      define_attribute? false
      source_attribute :category_id
      temporal_keys {nil, :valid_at}
    end

    belongs_to :resident, Rescord.Residents.Resident do
      public? true
      define_attribute? false
      source_attribute :resident_id
      temporal_keys {nil, :valid_at}
    end
  end

  calculations do
    # What a page shows as the state: an approved expense that a member paid
    # is still to pay back, and a list filters on that.
    calculate :status,
              :atom,
              expr(if state == :approved and paid_by == :member, do: :to_pay_back, else: state) do
      public? true
      constraints one_of: [:submitted, :approved, :to_pay_back, :reimbursed, :declined]

      description "The state for a person: `to_pay_back` is an approved expense that a member paid"
    end
  end

  aggregates do
    count :receipt_count, :receipts do
      public? true
    end
  end
end
