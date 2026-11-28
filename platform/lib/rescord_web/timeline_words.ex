defmodule RescordWeb.TimelineWords do
  @moduledoc """
  The words of an event of the timeline of a resident (ADR 0035): what
  happened, for a person to read. A page never shows the atom of a value.

  `names` has the words that an event does not hold itself:
  `%{locations: %{id => name}, groups: %{id => words}}`. The words of a
  group are those of `group/1`.
  """

  alias RescordWeb.{JournalWords, ResidentWords}

  @doc "What an event of the timeline was, in one line of words."
  def event(%{subject: :entry, record: entry}, _names) do
    [JournalWords.kind(entry.kind), JournalWords.facts(entry), entry.note]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(". ")
  end

  def event(%{subject: :name, kind: :started, record: record}, _names),
    do: "Got the name #{record.name}"

  def event(%{subject: :name, kind: :changed, record: record}, _names),
    do: "The name changed to #{record.name}"

  def event(%{subject: :name, kind: :ended}, _names), do: "The name was removed"

  def event(%{subject: :arrival, kind: :ended}, _names), do: "The arrival was removed"

  def event(%{subject: :arrival, kind: kind, record: record}, _names) do
    start = if kind == :started, do: "Arrival recorded", else: "The arrival was corrected"
    "#{start}: #{ResidentWords.arrival(record.kind)}, on #{ResidentWords.date(record.arrived_on)}"
  end

  def event(%{subject: :departure, kind: :ended}, _names), do: "The departure was withdrawn"

  def event(%{subject: :departure, kind: kind, record: record}, _names) do
    start = if kind == :started, do: "Departure recorded", else: "The departure was corrected"

    "#{start}: #{ResidentWords.departure(record.kind)}, on " <>
      ResidentWords.date(record.departed_on)
  end

  def event(%{subject: :absence, kind: :ended}, _names), do: "Came back"

  def event(%{subject: :absence, record: record}, _names), do: "Went away: #{record.reason}"

  def event(%{subject: :placement, kind: kind, record: record}, names) do
    place = Map.get(names.locations, record.location_id, "a location that is not here now")

    case kind do
      :started -> "Placed in #{place}"
      :changed -> "Moved to #{place}"
      :ended -> "Left #{place}"
    end
  end

  # A condition of the resident (ADR 0083). Its start is its diagnosis,
  # which is an entry.
  def event(%{subject: :episode, kind: :resolved, record: record} = event, _names) do
    "#{condition(event)} was resolved. Its last day was #{ResidentWords.date(record.ended_on)}"
  end

  def event(%{subject: :episode, kind: :reopened} = event, _names),
    do: "#{condition(event)} was opened again: it was not over"

  def event(%{subject: :group_member, kind: kind, record: record}, names) do
    group = Map.get(names.groups, record.group_id, "a group that is not here now")

    case kind do
      :ended -> "Left #{group}"
      _joined -> "Joined #{group}"
    end
  end

  defp condition(%{condition: name}) when is_binary(name), do: name
  defp condition(_event), do: "A condition that is not in the list now"

  @doc """
  A group in the words of a sentence: `the group The nursery` for a group
  with a name of its own, `the group of Fern and Sage` for a group with
  members and no name, and words for a group with neither.
  """
  def group(%{name: name}) when is_binary(name), do: "the group #{name}"
  def group(%{members: []}), do: "a group that has no members now"
  def group(%{members: members}), do: "the group of #{names_of(members)}"

  defp names_of(members) do
    names =
      members
      |> Enum.map(&(&1.resident.name || "a resident with no name"))
      |> Enum.sort()

    case names do
      [one] -> one
      names -> Enum.join(Enum.drop(names, -1), ", ") <> " and " <> List.last(names)
    end
  end

  @doc "The subjects that have words, for the test that holds them."
  def subjects,
    do: [:entry, :name, :arrival, :departure, :absence, :placement, :group_member, :episode]
end
