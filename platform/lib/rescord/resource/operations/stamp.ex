defmodule Rescord.Resource.Operations.Stamp do
  @moduledoc """
  Gives an action call its operation id, and records the operation id of the
  call that ran it as its causation id (ADR 0101).

  AshPaperTrail writes both on the version of the call, from
  `context.paper_trail_metadata`, which no nested call gets. The change also
  puts the operation id in the shared context, under `rescord`, which each
  nested call and each inline listener gets with
  `Rescord.Correlation.context/1` or from the scope of Ash: there it is the
  cause.

  A bulk call is one operation: each changeset of a batch gets the same
  ids. A batch is a call of its own, so a bulk action of more than one batch
  has an operation id for each batch, as AshPaperTrail has a correlation id
  for each batch when the caller gives none.
  """

  use Ash.Resource.Change

  # The change reads and writes the context only.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, _context), do: put(changeset, ids(changeset))

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  @impl true
  def batch_change([], _opts, _context), do: []

  def batch_change([first | _rest] = changesets, _opts, _context) do
    ids = ids(first)
    Enum.map(changesets, &put(&1, ids))
  end

  defp ids(changeset) do
    %{
      operation_id: Ash.UUIDv7.generate(),
      causation_id: get_in(changeset.context, [:shared, :rescord, :operation_id])
    }
  end

  defp put(changeset, %{operation_id: operation_id} = ids) do
    Ash.Changeset.set_context(changeset, %{
      paper_trail_metadata: ids,
      shared: %{rescord: %{operation_id: operation_id}}
    })
  end
end
