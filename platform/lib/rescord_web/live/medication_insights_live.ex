defmodule RescordWeb.MedicationInsightsLive do
  @moduledoc """
  The courses of medication of three weeks around today, at
  `/o/<short name>/insights/medication` (ADR 0122): who is on what now,
  and were the doses given?

  A time line has a row for each course that runs in the two weeks before
  today and the week after: a link to its prescription, a note in words,
  and a bar for its days, with a tick for each dose given, a ring for each
  dose that was due and not given, and a dotted line at now.

  Each member can open the page: it reads the journal and the tasks as
  that member.
  """

  use RescordWeb, :live_view

  import RescordWeb.ChartComponents
  import RescordWeb.InsightComponents

  alias Rescord.{Accounts, Journal, Tasks}
  alias RescordWeb.{Chart, JournalWords, Locale}

  @before 14
  @ahead 6

  @impl true
  def mount(_params, _session, socket) do
    organisation = socket.assigns.organisation
    options = [actor: socket.assigns.current_user, tenant: organisation]
    today = Accounts.today(organisation)
    first = Date.add(today, -@before)
    last = Date.add(today, @ahead)
    now = DateTime.utc_now()

    {:ok, courses} = Journal.courses(first, last, options)

    {:ok, missed} =
      Tasks.missed_doses(Enum.map(courses, & &1.id), first, last, [now: now] ++ options)

    {:ok,
     assign(socket,
       page_title: "Medication courses",
       first: first,
       last: last,
       now: Accounts.local_time(organisation, now),
       courses: Enum.map(courses, &Map.put(&1, :missed, Map.get(missed, &1.id, [])))
     )}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp ticks(first, last) do
    for date <- Date.range(first, last), Date.day_of_week(date) == 1 do
      %{x: Chart.day_x(date, first, last), label: Locale.short_date(date)}
    end
  end

  defp rows(courses, organisation, first, last) do
    for course <- courses do
      local = &Accounts.local_time(organisation, &1)

      %{
        id: "course-#{course.id}",
        name: "#{course.medication} for #{resident(course)}",
        href:
          ~p"/o/#{organisation.short_name}/residents/#{course.resident_id}/journal?entry=#{course.entry_id}",
        note: note(course),
        bars: [
          Map.put(
            Chart.span(course.starts_on, course.ends_on || last, first, last),
            :open,
            is_nil(course.ends_on)
          )
        ],
        marks:
          Enum.map(course.given, &%{kind: "given", x: Chart.instant_x(local.(&1), first, last)}) ++
            Enum.map(
              course.missed,
              &%{kind: "missed", x: Chart.instant_x(local.(&1), first, last)}
            )
      }
    end
  end

  defp resident(%{resident: nil}), do: "a resident with no name"
  defp resident(%{resident: name}), do: name

  defp note(course) do
    what =
      [course.dose, course.route && JournalWords.route(course.route)]
      |> Enum.reject(&(&1 in [nil, ""]))

    days =
      case course.ends_on do
        nil -> "from #{Locale.date(course.starts_on)}, with no last day"
        ends_on -> "#{Locale.date(course.starts_on)} to #{Locale.date(ends_on)}"
      end

    given =
      case course.given do
        [] -> "No dose given"
        given -> Locale.count(length(given), "dose given", "doses given")
      end

    missed =
      case course.missed do
        [] -> ""
        missed -> ", #{Locale.count(length(missed), "dose", "doses")} due and not given"
      end

    Enum.join(what ++ [days], ", ") <> ". #{given}#{missed} in these weeks."
  end

  defp summary([]), do: "No course of medication runs in these three weeks."

  defp summary(courses) do
    residents = courses |> Enum.map(& &1.resident_id) |> Enum.uniq() |> length()
    given = courses |> Enum.map(&length(&1.given)) |> Enum.sum()
    missed = courses |> Enum.map(&length(&1.missed)) |> Enum.sum()

    "#{Locale.count(length(courses), "course runs", "courses run")} in these three weeks, " <>
      "for #{Locale.count(residents, "resident", "residents")}. " <>
      "#{Locale.count(given, "dose was", "doses were")} given, and " <>
      "#{Locale.count(missed, "dose was", "doses were")} due and not given."
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:reports}
    >
      <.header icon={Icons.section(:insights)}>
        <:crumb navigate={~p"/o/#{@organisation.short_name}/reports"}>Reports</:crumb>
        Medication courses
        <:subtitle>Who at {@organisation.name} is on what now, and were the doses given?</:subtitle>
      </.header>

      <section aria-labelledby="courses-heading">
        <h2 id="courses-heading">Courses of three weeks</h2>
        <p>
          The courses of medication that run on a day from {Locale.date(@first)} to {Locale.date(
            @last
          )}, each from its first day to its last. A course with no last day is
          dashed. A tick is a dose given, a ring a dose that a task asked for and that was not
          given, and the dotted line is now.
        </p>
        <.key items={[
          {"up", "A course"},
          {"open", "A course with no last day"},
          {"given", "A dose given"},
          {"missed", "A dose due and not given"}
        ]} />
        <.timeline
          id="courses"
          label="The courses"
          summary={summary(@courses)}
          ticks={ticks(@first, @last)}
          rows={rows(@courses, @organisation, @first, @last)}
          now={Chart.instant_x(@now, @first, @last)}
        />
      </section>
    </Layouts.app>
    """
  end
end
