defmodule Rescord.History do
  @moduledoc """
  Reads the versions of the records of a temporal resource as changes, with
  no database (ADR 0035).

  A temporal resource keeps each version of a record as a row with a period
  (ADR 0012). The first version of a record is where it started, each later
  version is a change, and a last version whose period has an end is where
  it ended. A domain reads the versions of a resource, and this module says
  what happened and when.

  ## Examples

      iex> versions = [
      ...>   %{id: "a", valid_at: %{lower: ~U[2026-11-16 08:00:00Z], upper: ~U[2026-11-16 09:00:00Z]}, user_id: "u"},
      ...>   %{id: "a", valid_at: %{lower: ~U[2026-11-16 09:00:00Z], upper: ~U[2026-11-16 10:00:00Z]}, user_id: "v"}
      ...> ]
      iex> for change <- Rescord.History.changes(versions), do: {change.kind, change.at}
      [
        started: ~U[2026-11-16 08:00:00Z],
        changed: ~U[2026-11-16 09:00:00Z],
        ended: ~U[2026-11-16 10:00:00Z]
      ]
  """

  @typedoc """
  One change of a record:

    * `kind` - `:started`, `:changed` or `:ended`;
    * `at` - the instant of the change;
    * `record` - the version that the change made. For an end, it is the
      last version of the record;
    * `user_id` - the user who made the change. The versions do not say who
      ended a record, so an end has `nil`.
  """
  @type change :: %{
          kind: :started | :changed | :ended,
          at: DateTime.t(),
          record: map,
          user_id: String.t() | nil
        }

  @doc """
  The changes of the records of a list of versions, in the order of time.
  A version is a record with `id`, `valid_at` and `user_id`.
  """
  @spec changes([map]) :: [change]
  def changes(versions) do
    versions
    |> Enum.group_by(& &1.id)
    |> Enum.flat_map(fn {_id, rows} ->
      of_record(Enum.sort_by(rows, & &1.valid_at.lower, DateTime))
    end)
    |> Enum.sort_by(& &1.at, DateTime)
  end

  defp of_record(rows) do
    made =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, index} ->
        %{
          kind: kind(row, index),
          at: row.valid_at.lower,
          record: row,
          user_id: Map.get(row, :user_id)
        }
      end)

    last = List.last(rows)

    # A record that a member archived has its end in its last version.
    if last.valid_at.upper && not archived?(last),
      do: made ++ [%{kind: :ended, at: last.valid_at.upper, record: last, user_id: nil}],
      else: made
  end

  defp kind(row, index) do
    cond do
      archived?(row) -> :ended
      index == 0 -> :started
      true -> :changed
    end
  end

  defp archived?(row), do: not is_nil(Map.get(row, :archived_at))
end
