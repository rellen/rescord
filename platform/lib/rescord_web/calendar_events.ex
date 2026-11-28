defmodule RescordWeb.CalendarEvents do
  @moduledoc """
  Turns what a calendar feed holds into the events of a calendar
  (ADR 0074): the words of each event, and its link to the record in
  Rescord. `Rescord.Calendars.entries/4` gives the entries, and
  `Rescord.Calendars.ICalendar` writes the events as text.

  A feed leaves Rescord: a calendar service keeps a copy of it. So an event
  holds the least that is useful.

    * It never holds the name or the address of a member.
    * The words that a person wrote (the note of a task, the reason that a
      task was skipped, the reason of an absence) are there only when the
      feed says `with_notes`.
    * The link opens the record in Rescord, where a person signs in.
  """

  use RescordWeb, :verified_routes

  alias Rescord.{Accounts, Tasks}
  alias RescordWeb.{InventoryWords, TaskWords}

  # A task is due at an instant. A calendar draws an event with a length,
  # and this is the least length that each app draws as a block.
  @minutes 15

  @doc "The length of the event of a task, in minutes."
  @spec minutes() :: pos_integer
  def minutes, do: @minutes

  @doc "The address of a feed: the address that a calendar app reads, with the token."
  @spec address(map, String.t()) :: String.t()
  def address(organisation, token) when is_binary(token) do
    url(~p"/o/#{organisation.short_name}/calendar.ics?#{[token: token]}")
  end

  @doc "The calendar of a feed: its name, and the time zone of the organisation."
  @spec calendar(map, map) :: Rescord.Calendars.ICalendar.calendar()
  def calendar(feed, organisation), do: %{name: feed.name, time_zone: organisation.time_zone}

  @doc "The events of the entries of a feed, in the order of the entries."
  @spec events([Rescord.Calendars.entry()], map, map) :: [Rescord.Calendars.ICalendar.event()]
  def events(entries, feed, organisation) do
    host = RescordWeb.Endpoint.host()
    Enum.map(entries, &event(&1, feed, organisation, host))
  end

  defp event(%{kind: :task, record: task, at: at}, feed, organisation, host) do
    names = Tasks.subject_names(task)
    kind = kind(task)
    day = Accounts.local_date(organisation, at)

    link =
      url(~p"/o/#{organisation.short_name}/tasks?#{[day: Date.to_iso8601(day)]}") <>
        "#task-#{task.id}"

    %{
      uid: "task-#{task.id}@#{host}",
      starts: at,
      minutes: @minutes,
      summary: task_summary(task, names),
      description:
        lines([
          kind && "Kind: #{kind}",
          names != [] && "For: #{Enum.join(names, ", ")}",
          "State: #{state(task, feed)}",
          feed.with_notes && task.note,
          "Open in Rescord: #{link}"
        ]),
      url: link,
      categories: List.wrap(kind),
      status: if(task.state == :skipped, do: :cancelled, else: :confirmed)
    }
  end

  defp event(
         %{kind: :return, record: resident, absence: absence, on: on},
         feed,
         organisation,
         host
       ) do
    link = url(~p"/o/#{organisation.short_name}/residents/#{resident.id}")

    %{
      uid: "absence-#{absence.id}@#{host}",
      starts: on,
      summary: "Expected back: #{resident.name || "A resident with no name"}",
      description:
        lines([
          feed.with_notes && "Away: #{absence.reason}",
          "Open in Rescord: #{link}"
        ]),
      url: link,
      status: :confirmed
    }
  end

  defp event(
         %{kind: :expiry, record: item, lot: lot, level: level, on: on},
         _feed,
         organisation,
         host
       ) do
    link = url(~p"/o/#{organisation.short_name}/inventory/#{item.id}")

    %{
      uid: "lot-#{lot.id}@#{host}",
      starts: on,
      summary: "Expires: #{item.name} (#{InventoryWords.lot(lot)})",
      description:
        lines([
          "In stock: #{InventoryWords.quantity(level, item)}",
          "Open in Rescord: #{link}"
        ]),
      url: link,
      status: :confirmed
    }
  end

  # The state of a task is a word at the start of the line: a calendar
  # shows no shape and no colour of ours.
  defp task_summary(task, names) do
    prefix =
      case task.state do
        :done -> "Done: "
        :skipped -> "Skipped: "
        _due -> ""
      end

    case names do
      [] -> prefix <> task.title
      names -> "#{prefix}#{task.title} (#{Enum.join(names, ", ")})"
    end
  end

  defp state(%{state: :skipped, skip_reason: reason}, %{with_notes: true})
       when is_binary(reason),
       do: "#{TaskWords.phase(:skipped)}. #{reason}"

  defp state(%{state: state}, _feed), do: TaskWords.phase(state)

  defp kind(%{kind: %{label: label}}) when not is_nil(label), do: to_string(label)
  defp kind(_task), do: nil

  defp lines(lines) do
    lines
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.join("\n")
  end
end
