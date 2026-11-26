defmodule Rescord.Photos.AlbumPhoto do
  @moduledoc """
  A photo in an album (ADR 0055). The photo and the album are of the same
  resident (`Rescord.Photos.Validations.SameResident`).

  The same photo can go into the same album again after it came out, so the
  removal ends the period of the tie and leaves no row for the time after
  (`archive?: false`).
  """

  use Rescord.Resource,
    domain: Rescord.Photos,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "album_photos"

    custom_indexes do
      index [:photo_id]
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :add do
      description "Puts a photo in an album"
      accept [:album_id, :photo_id]
      validate Rescord.Photos.Validations.SameResident
    end

    destroy :take_out do
      description "Takes a photo out of an album"
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
  end

  relationships do
    belongs_to :album, Rescord.Photos.Album do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :photo, Rescord.Photos.Photo do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  identities do
    identity :unique_photo, [:album_id, :photo_id], message: "is in the album already"
  end
end
