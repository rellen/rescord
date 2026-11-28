defmodule Rescord.Transfers.Changes.SendTransfer do
  @moduledoc """
  Gives a new transfer its two refuges, its sender, its parts and its copy
  (ADR 0042 and ADR 0043).

  The refuges come from the arguments, so the policy can read them. After
  the policy, in a `before_action` hook, the change:

    * refuses a refuge that is not an accepted partner of the sender;
    * refuses a part that Rescord does not know;
    * reads the resident in the schema of the sender, as the actor, and
      writes the copy (`Rescord.Transfers.Snapshot`). A resident that the
      actor cannot read is refused with the words of a resident that is
      not there.

  It copies no file (ADR 0100). It writes the sources of the files of the
  copy beside it, with the state `sending`, and
  `Rescord.Transfers.Changes.StartCopy` emits `:transfer_started`: a job
  copies the files after the commit. A copy with no file is `sent` at
  once.

  `take_copy/3` is the part that `Rescord.Transfers.Changes.ExportTransfer`
  shares.
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
    |> Changeset.before_action(&send_copy(&1, context.actor))
  end

  defp send_copy(changeset, actor) do
    from_id = Changeset.get_attribute(changeset, :from_organisation_id)
    to_id = Changeset.get_attribute(changeset, :to_organisation_id)

    if partners?(from_id, to_id) do
      changeset = take_copy(changeset, actor, from_id)
      sources = changeset.context[:sources] || []

      changeset
      |> Changeset.force_change_attribute(:state, if(sources == [], do: :sent, else: :sending))
      |> Changeset.force_change_attribute(:sources, if(sources != [], do: sources))
      |> Changeset.force_change_attribute(:files_total, length(sources))
    else
      Changeset.add_error(changeset, field: :partner_id, message: "is not a partner refuge")
    end
  end

  @doc """
  Checks the parts, reads the resident in the schema of the refuge
  `from_id` as `actor`, and gives the changeset the copy, the parts, the
  resident and its name. The sources of the files go into the context of
  the changeset, under `:sources`: for each file its id in the copy, its
  key in the store of `from_id`, and its type.
  """
  def take_copy(changeset, actor, from_id) do
    parts = changeset |> Changeset.get_argument(:parts) |> List.wrap() |> Enum.uniq()

    if Enum.any?(parts, &(&1 not in Snapshot.parts())) do
      Changeset.add_error(changeset,
        field: :parts,
        message: "has a part that Rescord does not know"
      )
    else
      organisation = Accounts.organisation_of("org_" <> from_id)
      resident_id = Changeset.get_argument(changeset, :resident_id)

      case Snapshot.build(resident_id, parts, actor: actor, tenant: organisation) do
        {:ok, snapshot, sources} ->
          changeset
          |> Changeset.force_change_attribute(
            :parts,
            Enum.filter(Snapshot.parts(), &(&1 in parts))
          )
          |> Changeset.force_change_attribute(:snapshot, snapshot)
          |> Changeset.force_change_attribute(:resident_id, resident_id)
          |> Changeset.force_change_attribute(:resident_name, snapshot["facts"]["name"])
          |> Changeset.set_context(%{sources: sources})

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

  @doc false
  def user_id(%Accounts.User{id: id}), do: id
  def user_id(_actor), do: nil
end
