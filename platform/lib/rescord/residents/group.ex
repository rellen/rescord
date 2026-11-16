defmodule Rescord.Residents.Group do
  @moduledoc """
  A set of residents that the organisation manages together, and that is not
  a family: a bonded pair, a herd, a set in quarantine (`docs/domain.md`,
  section 5.4).

  `Rescord.Residents.GroupMember` ties a resident to the group for a time. A
  resident can be in more than one group at one time.

  A group has words that say how its members are related. Rescord calculates
  them (`Rescord.Residents.Kinship`), and a member can replace them: the
  attribute `description` holds the words of the member, and is empty when
  the calculated words apply.

  An organisation closes a group that is no more. That archives it.
  """

  use Rescord.Resource,
    domain: Rescord.Residents,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "groups"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :form do
      description "Makes a group, with its first members"
      accept [:name, :kind_id, :description]
      argument :resident_ids, {:array, :uuid}, default: []
      change Rescord.Residents.Changes.JoinGroup
    end

    update :revise do
      accept [:name, :kind_id, :description]
    end

    destroy :close do
      description "Closes a group that is no more. The row and its history stay"
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
      public? true
      constraints min_length: 1, max_length: 80

      description "A name that the organisation gives the group. Without one, a page names its members"
    end

    attribute :description, :string do
      public? true
      constraints min_length: 1, max_length: 200

      description "The words of a member for how the residents are related, in place of the calculated words"
    end
  end

  relationships do
    belongs_to :kind, Rescord.Lists.GroupKind do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :members, Rescord.Residents.GroupMember do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
