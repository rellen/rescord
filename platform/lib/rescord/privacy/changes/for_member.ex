defmodule Rescord.Privacy.Changes.ForMember do
  @moduledoc """
  A request that a person records for the member of the argument
  `member_id`: a member now, or a former member (ADR 0105). The request
  names the member and its user. With no day of receipt, it arrived today.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts

  @impl true
  def change(changeset, _opts, _context) do
    id = Ash.Changeset.get_argument(changeset, :member_id)

    case Accounts.member_with_former(id, tenant: changeset.tenant, authorize?: false) do
      {:ok, %{} = member} ->
        changeset
        |> Ash.Changeset.force_change_attribute(:user_id, member.user_id)
        |> Ash.Changeset.force_change_attribute(:member_id, member.id)
        |> default_today()

      _none ->
        Ash.Changeset.add_error(changeset,
          field: :member_id,
          message: "is no member of the organisation"
        )
    end
  end

  defp default_today(changeset) do
    case Ash.Changeset.get_attribute(changeset, :received_on) do
      nil ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :received_on,
          Accounts.today(changeset.tenant)
        )

      _day ->
        changeset
    end
  end
end
