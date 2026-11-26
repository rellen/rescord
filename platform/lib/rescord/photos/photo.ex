defmodule Rescord.Photos.Photo do
  @moduledoc """
  A photo of a resident, with a caption and a date (ADR 0055).

  A photo is one of two kinds:

    * A photo that a person adds on the page of the photos. `add` takes the
      bytes in the argument `content`, and `Rescord.Photos.Changes.StorePhoto`
      puts the photo and its thumbnail in the store, at
      `<organisation id>/photos/<id>` and `<organisation id>/thumbnails/<id>`.
    * A photo of a journal entry that a person uses as a photo: puts in an
      album, or makes the profile picture. `adopt` names the attachment, and
      `Rescord.Photos.Changes.AdoptAttachment` takes the resident, the date
      and the keys of the files from the attachment and its entry. The two
      records name one file in the store, and Rescord makes no copy.

  The date is the day that the photo shows: the one that the person gives,
  or the one that the camera recorded, or today. The caption is optional.
  Both change with `describe`, and the history keeps each version.

  No action takes the keys, the type, the size, the author or the
  attachment as input. A removal archives the record, and the files stay
  in the store. It ends the ties of the photo to its albums and to the
  profile picture in the same transaction (ADR 0036).
  """

  use Rescord.Resource,
    domain: Rescord.Photos,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Photos

  postgres do
    table "photos"

    custom_indexes do
      index [:resident_id]
      index [:attachment_id]
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :add do
      description "Adds a photo of a resident"
      accept [:resident_id, :caption, :taken_on]
      argument :content, :binary, allow_nil?: false, sensitive?: true
      change Photos.Changes.SetAuthor
      change Photos.Changes.StorePhoto
      validate Photos.Validations.NotAfterToday
    end

    create :adopt do
      description "Uses a photo of a journal entry as a photo of its resident"
      accept [:caption]
      argument :attachment_id, :uuid, allow_nil?: false
      change Photos.Changes.SetAuthor
      change Photos.Changes.AdoptAttachment
    end

    update :describe do
      description "Changes the caption and the date of a photo"
      accept [:caption, :taken_on]
      require_atomic? false
      validate Photos.Validations.NotAfterToday
    end

    destroy :remove do
      description "Removes a photo. Its files stay in the store, and its ties end"
      require_atomic? false
      change Photos.Changes.EndPhotoTies
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

    attribute :caption, :string do
      public? true
      constraints max_length: 500, trim?: true
      description "What the photo shows, in the words of a member"
    end

    attribute :taken_on, :date do
      allow_nil? false
      public? true
      description "The day that the photo shows"
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
      description "The size of the photo in the store, in bytes"
    end

    attribute :key, :string do
      allow_nil? false
      public? true
      writable? false
      description "The key of the photo in the store"
    end

    attribute :thumbnail_key, :string do
      public? true
      writable? false
      description "The key of the thumbnail in the store, or nil for an old journal photo"
    end

    # An attachment is not temporal, and the database holds no key from a
    # table with a period to one with none here, so this is a plain id.
    attribute :attachment_id, :uuid do
      public? true
      writable? false
      description "The journal attachment that this photo uses, or nil"
    end

    attribute :author_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end
  end

  relationships do
    belongs_to :resident, Rescord.Residents.Resident do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :attachment, Rescord.Journal.Attachment do
      public? true
      define_attribute? false
      temporal_keys {:valid_at, nil}
    end

    has_many :album_photos, Rescord.Photos.AlbumPhoto do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
