defmodule Rescord.Transfers.Changes.RecordCard do
  @moduledoc """
  Gives a new partner on another server the facts of its partner card
  (`Rescord.Transfers.Keys.read_card/1`), the refuge that records it, and
  the person who does. Text that is not a card is refused.
  """

  use Ash.Resource.Change

  alias Rescord.Transfers.{Crypto, Keys}

  @impl true
  def change(changeset, _opts, context) do
    changeset =
      changeset
      |> Ash.Changeset.force_change_attribute(
        :organisation_id,
        Ash.Changeset.get_argument(changeset, :organisation_id)
      )
      |> Ash.Changeset.force_change_attribute(:recorded_by_id, user_id(context.actor))

    case Keys.read_card(Ash.Changeset.get_argument(changeset, :card)) do
      {:ok, card} ->
        changeset
        |> Ash.Changeset.force_change_attribute(:refuge_id, card.refuge_id)
        |> Ash.Changeset.force_change_attribute(:name, card.name)
        |> Ash.Changeset.force_change_attribute(:sign_public, card.sign_public)
        |> Ash.Changeset.force_change_attribute(:box_public, card.box_public)
        |> Ash.Changeset.force_change_attribute(
          :fingerprint,
          Crypto.fingerprint(card.sign_public, card.box_public)
        )

      :error ->
        Ash.Changeset.add_error(changeset,
          field: :card,
          message: "is not a partner card of Rescord"
        )
    end
  end

  defp user_id(%Rescord.Accounts.User{id: id}), do: id
  defp user_id(_actor), do: nil
end
