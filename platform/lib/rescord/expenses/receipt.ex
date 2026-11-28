defmodule Rescord.Expenses.Receipt do
  @moduledoc """
  A file of an expense: a photo of a receipt, or an invoice as a PDF
  (ADR 0082). It follows the attachments of the journal (ADR 0041).

  The record holds the name of the file, its type and its size, and the key
  of the file in the store (`Rescord.Storage`). The bytes are in the store,
  and never in the database.

  `attach` takes the bytes in the argument `content`.
  `Rescord.Expenses.Changes.StoreReceipt` checks the file with
  `Rescord.Storage.Upload`: a JPEG, a PNG, a GIF, a WebP image or a PDF, of
  20 MB at most, with the type read from the first bytes. A photo loses its
  metadata, the GPS position with the rest, and gets a thumbnail
  (ADR 0055): a person often takes the photo of a receipt at home.

  A person attaches a receipt to an expense that they can read, in any
  state: a proof of the payment can come after the decision. `remove` takes
  off a receipt that the person added, while the expense waits for a
  decision or after it was declined. `discard` takes off any receipt, and is
  for a person who manages the expenses. Both archive the record, and the
  file stays in the store.

  No action takes the type, the size, the keys or the author as input. This
  resource is not temporal: a receipt does not change.
  """

  use Rescord.Resource,
    domain: Rescord.Expenses,
    temporal?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Expenses.{Changes, Validations}

  postgres do
    table "expense_receipts"

    custom_indexes do
      index [:expense_id]
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :attach do
      description "Attaches a file to an expense"
      accept [:expense_id, :name]
      argument :content, :binary, allow_nil?: false, sensitive?: true
      change Changes.SetAuthor
      change Changes.StoreReceipt
      validate Validations.ExpenseOfActor, before_action?: true
    end

    destroy :remove do
      description "Takes a file off an expense that waits or that was declined. The file stays in the store"
      require_atomic? false
      validate Validations.ExpenseOpen, before_action?: true
    end

    destroy :discard do
      description "Takes a file off an expense in any state. The file stays in the store"
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

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200, trim?: true
      description "The name of the file, as the person gave it"
    end

    attribute :content_type, :string do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :size, :integer do
      allow_nil? false
      public? true
      writable? false
      description "The size of the file, in bytes"
    end

    attribute :key, :string do
      allow_nil? false
      public? true
      writable? false
      description "The key of the file in the store"
    end

    attribute :thumbnail_key, :string do
      public? true
      writable? false
      description "The key of the thumbnail of a photo in the store, or nil for a PDF"
    end

    attribute :author_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :expense, Rescord.Expenses.Expense do
      allow_nil? false
      public? true
    end
  end
end
