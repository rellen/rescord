defmodule Rescord.Journal.Attachment do
  @moduledoc """
  A file of a journal entry: a photo, or the report of a vet as a PDF
  (`docs/domain.md`, section 5.6, and ADR 0041).

  The record holds the name of the file, its type and its size, and the key
  of the file in the store (`Rescord.Storage`). The bytes are in the store,
  and never in the database.

  `attach` takes the bytes in the argument `content`.
  `Rescord.Journal.Changes.StoreAttachment` reads the type from the first
  bytes, and not from the name or from what the browser says: a JPEG, a
  PNG, a GIF, a WebP image or a PDF. It refuses another type, an empty
  file, and a file of more than 20 MB. A photo loses its metadata, the GPS
  position with the rest, and gets a thumbnail (ADR 0055). It puts the
  files in the store after the write, in the transaction, so a fault of the
  store writes no record.

  A removal archives the record, and the file stays in the store: a file
  has no period, and the history of the entry can name it. The author is
  the user who attached the file. No action takes it, the type, the size
  or the key as input.

  This resource is not temporal: an attachment does not change.
  """

  use Rescord.Resource,
    domain: Rescord.Journal,
    temporal?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Journal

  postgres do
    table "journal_attachments"

    custom_indexes do
      index [:entry_id]
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :attach do
      description "Attaches a file to a journal entry"
      accept [:entry_id, :name]
      argument :content, :binary, allow_nil?: false, sensitive?: true
      change Rescord.Accounts.Changes.SetAuthor
      change Journal.Changes.StoreAttachment
      validate Journal.Validations.EntryOfOrganisation, before_action?: true
    end

    destroy :remove do
      description "Takes the file off the entry. The file stays in the store"
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

    # A journal entry is temporal, and the database holds no key from a
    # table with no period to one with a period, so this is a plain id.
    attribute :entry_id, :uuid do
      allow_nil? false
      public? true
    end

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
      description "The key of the thumbnail of a photo in the store, or nil for a PDF (ADR 0055)"
    end

    attribute :display_key, :string do
      public? true
      writable? false

      description "The key of the display file of a photo in the store, which a page opens, or nil for a PDF, a GIF and a photo that has none yet (issue 34)"
    end

    attribute :author_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end

    create_timestamp :inserted_at
  end
end
