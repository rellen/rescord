defmodule Rescord.Transfers.Changes.AskPartner do
  @moduledoc """
  Gives a new partnership its two refuges and the person who asked: the
  refuge of the argument `organisation_id`, and the refuge with the short
  name of the argument `short_name`.

  A short name that no refuge has, and the short name of the refuge that
  asks, are refused with the same words, so the answer does not say which
  short names exist beyond what the person typed.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts

  @impl true
  def change(changeset, _opts, context) do
    from_id = Ash.Changeset.get_argument(changeset, :organisation_id)
    short_name = Ash.Changeset.get_argument(changeset, :short_name)

    changeset =
      changeset
      |> Ash.Changeset.force_change_attribute(:from_organisation_id, from_id)
      |> Ash.Changeset.force_change_attribute(:asked_by_id, user_id(context.actor))

    case partner(short_name) do
      %{id: to_id} when to_id != from_id ->
        Ash.Changeset.force_change_attribute(changeset, :to_organisation_id, to_id)

      _no_partner ->
        Ash.Changeset.add_error(changeset,
          field: :short_name,
          message: "names no other refuge"
        )
    end
  end

  defp partner(short_name) when is_binary(short_name),
    do: Accounts.organisation_by_short_name!(String.trim(short_name), authorize?: false)

  defp partner(_none), do: nil

  defp user_id(%Accounts.User{id: id}), do: id
  defp user_id(_actor), do: nil
end
