defmodule RescordWeb.TimelineComponents do
  @moduledoc """
  The parts of the timeline of a resident (ADR 0035 and ADR 0037): one
  event, with its time and its person.
  """

  use RescordWeb, :html

  alias Rescord.Accounts
  alias RescordWeb.{JournalWords, TimelineWords}

  @doc "One event of the timeline: its time in the organisation, its words and its person."
  attr :event, :any, required: true
  attr :organisation, :any, required: true
  attr :names, :any, required: true
  attr :people, :any, required: true
  attr :current_user, :any, required: true

  def timeline_event(assigns) do
    ~H"""
    <li data-subject={@event.subject}>
      <time datetime={DateTime.to_iso8601(@event.at)}>
        {when_words(@organisation, @event.at)}
      </time>
      <p><.icon :if={shape(@event)} name={shape(@event)} /> {TimelineWords.event(@event, @names)}</p>
      <small :if={person = person(@people, @event, @current_user)}>{person}</small>
    </li>
    """
  end

  # The shape of an event: the kind of an entry, or what happened to the
  # stay, the place, a condition or a group.
  defp shape(%{subject: :entry, record: entry}), do: Icons.entry_kind(entry.kind)
  defp shape(%{subject: :name}), do: "pencil"
  defp shape(%{subject: :arrival}), do: "door-in"
  defp shape(%{subject: :departure}), do: "door-out"
  defp shape(%{subject: :absence, kind: :ended}), do: "door-in"
  defp shape(%{subject: :absence}), do: "map-pin"
  defp shape(%{subject: :placement}), do: Icons.section(:housing)
  defp shape(%{subject: :episode, kind: :resolved}), do: "check"
  defp shape(%{subject: :episode, kind: :reopened}), do: "arrow-uturn-left"
  defp shape(%{subject: :episode}), do: Icons.section(:conditions)
  defp shape(%{subject: :group_member}), do: Icons.section(:groups)
  defp shape(_event), do: nil

  def when_words(organisation, instant),
    do: JournalWords.time(Accounts.local_time(organisation, instant))

  # The person of an event, or `nil` for an event that has none on record.
  # A root user is not a member, and reads their own events as their own.
  def person(_people, %{user_id: nil}, _user), do: nil

  def person(people, %{user_id: id}, user) do
    cond do
      Map.has_key?(people, id) -> people[id]
      id == user.id -> to_string(user.email)
      true -> "a person who is not a member now"
    end
  end
end
