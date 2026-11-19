defmodule Rescord.Transfers.Changes.SendTransfer do
  @moduledoc """
  Gives a new transfer its two refuges, its sender, its parts and its copy
  (ADR 0042).

  The refuges come from the arguments, so the policy can read them. After
  the policy, in a `before_action` hook, the change:

    * refuses a refuge that is not an accepted partner of the sender;
    * refuses a part that Rescord does not know;
    * reads the resident in the schema of the sender, as the actor, and
      writes the copy (`Rescord.Transfers.Snapshot`). A resident that the
      actor cannot read is refused with the words of a resident that is
      not there.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Ash.Changeset
  alias Rescord.Accounts
  alias Rescord.Transfers.{Partnership, Snapshot}

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.force_change_attribute(
      :from_organisation_id,
      Changeset.get_argument(changeset, :organisation_id)
    )
    |> Changeset.force_change_attribute(
      :to_organisation_id,
      Changeset.get_argument(changeset, :partner_id)
    )
    |> Changeset.force_change_attribute(:sent_by_id, user_id(context.actor))
    |> Changeset.before_action(&copy(&1, context.actor))
  end

  defp copy(changeset, actor) do
    from_id = Changeset.get_attribute(changeset, :from_organisation_id)
    to_id = Changeset.get_attribute(changeset, :to_organisation_id)
    parts = changeset |> Changeset.get_argument(:parts) |> List.wrap() |> Enum.uniq()

    cond do
      not partners?(from_id, to_id) ->
        Changeset.add_error(changeset, field: :partner_id, message: "is not a partner refuge")

      Enum.any?(parts, &(&1 not in Snapshot.parts())) ->
        Changeset.add_error(changeset,
          field: :parts,
          message: "has a part that Rescord does not know"
        )

      true ->
        organisation = Accounts.organisation_of("org_" <> from_id)
        resident_id = Changeset.get_argument(changeset, :resident_id)

        case Snapshot.build(resident_id, parts, actor: actor, tenant: organisation) do
          {:ok, snapshot} ->
            changeset
            |> Changeset.force_change_attribute(
              :parts,
              Enum.filter(Snapshot.parts(), &(&1 in parts))
            )
            |> Changeset.force_change_attribute(:snapshot, snapshot)
            |> Changeset.force_change_attribute(:resident_id, resident_id)
            |> Changeset.force_change_attribute(:resident_name, snapshot["facts"]["name"])

          :error ->
            Changeset.add_error(changeset,
              field: :resident_id,
              message: "is not a resident of this refuge"
            )
        end
    end
  end

  defp partners?(a, b) do
    Partnership
    |> Ash.Query.filter(
      state == :accepted and
        ((from_organisation_id == ^a and to_organisation_id == ^b) or
           (from_organisation_id == ^b and to_organisation_id == ^a))
    )
    |> Ash.exists?(authorize?: false)
  end

  defp user_id(%Accounts.User{id: id}), do: id
  defp user_id(_actor), do: nil
end
