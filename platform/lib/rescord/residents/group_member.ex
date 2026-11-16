defmodule Rescord.Residents.GroupMember do
  @moduledoc """
  A resident in a group, for a time. The period of the record is the time in
  the group: it starts when the resident joins, and it ends when the
  resident leaves. A read as of an instant gives the members at that
  instant.
  """

  use Rescord.Residents.Fact, table: "group_members", archive?: false

  actions do
    defaults [:read]

    create :join do
      accept [:resident_id, :group_id]
    end

    destroy :leave
  end

  relationships do
    belongs_to :group, Rescord.Residents.Group do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  identities do
    identity :unique_member, [:resident_id, :group_id], message: "is in this group already"
  end
end
