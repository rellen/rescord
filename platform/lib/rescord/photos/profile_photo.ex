defmodule Rescord.Photos.ProfilePhoto do
  @moduledoc """
  The profile picture of a resident: one of its photos, which the pages of
  the resident and the list of the residents show (ADR 0055). A resident has
  one at most at a time, and none at first.

  A change of the picture is a new version, so a read as of a past instant
  gives the picture of then. The removal of the photo ends the record in
  the same transaction (`Rescord.Photos.Changes.EndPhotoTies`).
  """

  use Rescord.Resource,
    domain: Rescord.Photos,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "profile_photos"

    custom_indexes do
      index [:photo_id]
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :choose do
      description "Makes a photo the profile picture of its resident"
      accept [:resident_id, :photo_id]
      validate Rescord.Photos.Validations.SameResident
    end

    update :change do
      description "Makes another photo of the resident its profile picture"
      accept [:photo_id]
      require_atomic? false
      validate Rescord.Photos.Validations.SameResident
    end

    destroy :clear do
      description "Leaves the resident with no profile picture"
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
    belongs_to :resident, Rescord.Residents.Resident do
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
    identity :unique_resident, [:resident_id], message: "has a profile picture already"
  end
end
