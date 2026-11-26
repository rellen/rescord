defmodule Rescord.Photos.Album do
  @moduledoc """
  A named set of the photos of one resident, for example "Recovery after
  surgery" or "For adoption" (ADR 0055). A photo can be in any number of
  albums of its resident, or in none: `Rescord.Photos.AlbumPhoto` is the
  tie.

  A removal archives the album and ends its ties in the same transaction
  (ADR 0036). The photos stay.
  """

  use Rescord.Resource,
    domain: Rescord.Photos,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "albums"

    custom_indexes do
      index [:resident_id]
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :make do
      description "Makes an album for the photos of a resident"
      accept [:resident_id, :name]
    end

    update :rename do
      accept [:name]
    end

    destroy :remove do
      description "Removes an album. Its photos stay"
      require_atomic? false
      change Rescord.Photos.Changes.EndAlbumTies
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
      constraints min_length: 1, max_length: 100, trim?: true
    end
  end

  relationships do
    belongs_to :resident, Rescord.Residents.Resident do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :album_photos, Rescord.Photos.AlbumPhoto do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
