defmodule Rescord.Accounts.Changes.Pseudonymise do
  @moduledoc """
  Gives an erased member the next number of Former member N in the
  organisation, and the instant of the erasure (ADR 0105). A number is
  never used again: the next one is one more than the largest, and the
  rows of erased members stay. An erasure that runs again after the restore of a
  dump (`Rescord.Privacy.reapply_erasures/0`) gives the number of its
  marker. The unique index of the number refuses a
  second erasure that took the same number at the same time.
  """

  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      changeset
      |> Ash.Changeset.force_change_attribute(
        :former_number,
        Ash.Changeset.get_argument(changeset, :former_number) || next_number(changeset)
      )
      |> Ash.Changeset.force_change_attribute(:erased_at, DateTime.utc_now())
    end)
  end

  defp next_number(changeset) do
    largest =
      changeset.resource
      |> Ash.Query.for_read(:with_former)
      |> Ash.Query.filter(not is_nil(former_number))
      |> Ash.max(:former_number, tenant: changeset.tenant, authorize?: false)

    case largest do
      {:ok, nil} -> 1
      {:ok, number} -> number + 1
    end
  end
end
