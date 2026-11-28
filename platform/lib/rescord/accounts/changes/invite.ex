defmodule Rescord.Accounts.Changes.Invite do
  @moduledoc """
  Invites the person with the address of the argument `email`.

  Before the member is made, the change finds the user of the address, or
  makes one.

  The email is not the work of this change. The action emits
  `:member_invited`, and `Rescord.Accounts.Actions.SendInvitation` sends
  the email in a job (ADR 0067).
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Accounts
  alias Rescord.Accounts.User

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      address = Ash.Changeset.get_argument(changeset, :email)
      user = find_or_make_user(address, changeset)

      if erased_here?(user, changeset.tenant) do
        Ash.Changeset.add_error(changeset,
          field: :email,
          message:
            "was erased from this organisation on request. A root user can erase the whole account, and the person is then invited as a new person"
        )
      else
        Ash.Changeset.force_change_attribute(changeset, :user_id, user.id)
      end
    end)
  end

  # The records of the organisation name a person erased here as Former
  # member N. The same account as a member again would put their name back
  # on them (ADR 0105).
  defp erased_here?(user, tenant) do
    Accounts.Member
    |> Ash.Query.for_read(:with_former)
    |> Ash.Query.filter(user_id == ^user.id and not is_nil(erased_at))
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end

  defp find_or_make_user(address, changeset) do
    case Accounts.user_by_email!(address, authorize?: false) do
      nil ->
        User
        |> Ash.Changeset.for_create(:for_invitation, %{email: address},
          context: Rescord.Correlation.context(changeset)
        )
        |> Ash.create!(authorize?: false)

      user ->
        user
    end
  end
end
