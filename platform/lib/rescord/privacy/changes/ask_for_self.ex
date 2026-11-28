defmodule Rescord.Privacy.Changes.AskForSelf do
  @moduledoc """
  A request that the actor makes from their own page (ADR 0105): it is
  about the actor and their member in the organisation, it arrived today,
  and the sign-in is the check of who asked.

  With no member of the actor, the change adds an error: a person who is
  not a member has nothing to ask of the organisation.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts

  @impl true
  def change(changeset, _opts, %{actor: %Accounts.User{id: id}} = context) do
    case Accounts.member_of_user(id, actor: context.actor, tenant: changeset.tenant) do
      {:ok, %{} = member} ->
        changeset
        |> Ash.Changeset.force_change_attribute(:user_id, id)
        |> Ash.Changeset.force_change_attribute(:member_id, member.id)
        |> Ash.Changeset.force_change_attribute(:how_received, :own_page)
        |> Ash.Changeset.force_change_attribute(:identity, "Signed in")
        |> Ash.Changeset.force_change_attribute(:received_on, Accounts.today(changeset.tenant))

      _none ->
        Ash.Changeset.add_error(changeset, field: :member_id, message: "is not a member here")
    end
  end

  def change(changeset, _opts, _context), do: changeset
end
