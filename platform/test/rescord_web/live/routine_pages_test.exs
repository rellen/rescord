defmodule RescordWeb.RoutinePagesTest do
  @moduledoc """
  Holds the page of the routines: what a member reads of a routine, the form
  of a new routine and of a change, the pause and the end of a routine, a
  routine for the doses of a prescription, and the words of a pattern.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Journal, Tasks}
  alias RescordWeb.TaskWords

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    today = Accounts.today(organisation)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists,
     options: options,
     today: today,
     tomorrow: Date.add(today, 1),
     biscuit: resident!(lists, options),
     path: ~p"/o/#{organisation.short_name}/routines",
     conn: sign_in(context.conn, member)}
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp submit(view, conn, selector, fields) do
    {:ok, view, _html} =
      view |> form(selector, fields) |> render_submit() |> follow_redirect(conn)

    {view, render_async(view)}
  end

  defp press(view, conn, event, id) do
    {:ok, view, _html} = view |> render_click(event, %{"id" => id}) |> follow_redirect(conn)
    {view, render_async(view)}
  end

  defp start!(context, facts \\ %{}) do
    %{
      title: "Hay and pellets",
      pattern: :daily,
      times: [~T[08:00:00], ~T[18:00:00]],
      starts_on: context.today
    }
    |> Map.merge(facts)
    |> Tasks.start_routine!(context.options)
  end

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    assert {:error, {:redirect, %{to: "/"}}} =
             build_conn() |> sign_in(outsider) |> live(context.path)

    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.path)
  end

  describe "the routines" do
    test "are on the page with when each repeats, what it is for, and its next task", context do
      start!(context, %{
        kind_id: context.lists.task_kind.feed,
        resident_ids: [context.biscuit.id],
        assignee_id: context.member.id,
        note: "Two scoops"
      })

      {view, html} = open(context.conn, context.path)

      assert html =~ "Rescord makes the tasks of a routine 14 days ahead."
      assert has_element?(view, "tbody td", "Hay and pellets")
      assert has_element?(view, "tbody td small", "Feed")
      assert has_element?(view, "tbody td small", "Two scoops")
      assert has_element?(view, "tbody td", "Each day, at 08:00 and 18:00")
      assert has_element?(view, "tbody td", "Biscuit")
      assert has_element?(view, "tbody td", to_string(context.member.email))
      assert has_element?(view, "[data-state=ok]", "Active")
      assert has_element?(view, "tbody td small", "Next:")
    end

    test "say so when there is none", context do
      {_view, html} = open(context.conn, context.path)
      assert html =~ "There is no routine yet."
    end

    test "say when one has not started, and when one is finished", context do
      start!(context, %{title: "Later", starts_on: Date.add(context.today, 5)})
      routine = start!(context, %{title: "Short"})

      # The last day of the routine was yesterday.
      Ash.Seed.update!(routine, %{
        starts_on: Date.add(context.today, -3),
        ends_on: Date.add(context.today, -1)
      })

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "[data-state=info]", "Not started")
      assert has_element?(view, "[data-state=none]", "Finished")
    end
  end

  describe "a new routine" do
    test "starts with the facts of the form, and has its tasks", context do
      {view, _html} = open(context.conn, context.path)

      {view, _html} =
        submit(view, context.conn, "#routine",
          routine: %{
            title: "Clean the water bottles",
            kind_id: context.lists.task_kind.clean,
            time_1: "07:30",
            time_2: "17:00",
            starts_on: Date.to_iso8601(context.tomorrow),
            resident_id: context.biscuit.id
          }
        )

      assert has_element?(view, "tbody td", "Each day, at 07:30 and 17:00")

      {:ok, tasks} = Tasks.day(context.tomorrow, context.options)
      assert Enum.map(tasks, & &1.title) == List.duplicate("Clean the water bottles", 2)
      assert Tasks.subject_names(hd(tasks)) == ["Biscuit"]
    end

    test "asks for the days of the week, or for a number, when the pattern needs one", context do
      {view, _html} = open(context.conn, context.path)

      refute has_element?(view, "#routine-weekdays")
      refute has_element?(view, "#routine_every")

      view |> form("#routine", routine: %{pattern: "weekly"}) |> render_change()
      assert has_element?(view, "#routine-weekdays legend", "Days of the week")
      assert has_element?(view, "#routine-weekdays input[type=checkbox]")
      refute has_element?(view, "#routine_every")

      view |> form("#routine", routine: %{pattern: "interval"}) |> render_change()
      refute has_element?(view, "#routine-weekdays")
      assert has_element?(view, "label", "Every how many days")

      view |> form("#routine", routine: %{pattern: "monthly"}) |> render_change()
      assert has_element?(view, "label", "Every how many months")
    end

    test "is on given days of the week", context do
      {view, _html} = open(context.conn, context.path)
      view |> form("#routine", routine: %{pattern: "weekly"}) |> render_change()

      {view, _html} =
        submit(view, context.conn, "#routine",
          routine: %{title: "Weigh each resident", weekdays: ["1", "4"], time_1: "09:00"}
        )

      assert has_element?(view, "tbody td", "Each Monday and Thursday, at 09:00")

      {:ok, [routine]} = Tasks.routines(context.options)
      assert %{pattern: :weekly, weekdays: [1, 4], times: [~T[09:00:00]]} = routine
    end

    test "is every number of months, a year ahead", context do
      {view, _html} = open(context.conn, context.path)
      view |> form("#routine", routine: %{pattern: "monthly"}) |> render_change()

      {view, _html} =
        submit(view, context.conn, "#routine",
          routine: %{title: "Yearly check", every: "12", time_1: "10:00", days_ahead: "400"}
        )

      assert has_element?(view, "tbody td", "Every 12 months, at 10:00")

      {:ok, [routine]} = Tasks.routines(context.options)
      assert %{pattern: :monthly, every: 12, days_ahead: 400} = routine
    end

    test "says what is wrong, and keeps what the member typed", context do
      {view, _html} = open(context.conn, context.path)
      view |> form("#routine", routine: %{pattern: "weekly"}) |> render_change()

      html =
        view
        |> form("#routine", routine: %{title: "Weigh each resident", time_1: "09:00"})
        |> render_submit()

      assert has_element?(
               view,
               "#routine p[role=alert]",
               "Weekdays needs one day of the week or more"
             )

      assert html =~ ~s(value="Weigh each resident")
      assert has_element?(view, "#routine-weekdays")
      assert {:ok, []} = Tasks.routines(context.options)
    end

    test "does not take a pattern that the page did not offer", context do
      {view, _html} = open(context.conn, context.path)

      render_submit(view, "save", %{
        "routine" => %{
          "title" => "X",
          "pattern" => "hourly",
          "time_1" => "09:00",
          "starts_on" => Date.to_iso8601(context.today)
        }
      })

      assert has_element?(view, "main p[role=alert]")
      assert {:ok, []} = Tasks.routines(context.options)
    end
  end

  describe "a routine on the page" do
    test "is changed on its own page, which has its facts", context do
      routine = start!(context, %{resident_ids: [context.biscuit.id], note: "Two scoops"})
      {view, html} = open(context.conn, context.path <> "/#{routine.id}/edit")

      assert html =~ "Change the routine Hay and pellets"
      assert has_element?(view, "#routine_title[value='Hay and pellets']")
      assert has_element?(view, "#routine_time_1[value='08:00']")
      assert has_element?(view, "#routine_time_2[value='18:00']")
      assert has_element?(view, "#routine_resident_id option[selected]", "Biscuit")
      # The list and the form of a new routine are not on this page.
      refute has_element?(view, "#new-routine")
      refute has_element?(view, "table")

      {view, _html} =
        submit(view, context.conn, "#routine", routine: %{title: "Hay only", time_2: ""})

      assert has_element?(view, "tbody td", "Hay only")
      assert has_element?(view, "tbody td", "Each day, at 08:00")

      {:ok, tasks} = Tasks.day(context.tomorrow, context.options)
      assert Enum.map(tasks, & &1.title) == ["Hay only"]
    end

    test "goes to the list when the routine of the address is not there", context do
      assert {:error, {:live_redirect, %{to: to}}} =
               live(context.conn, context.path <> "/#{Ash.UUID.generate()}/edit")

      assert to == context.path
    end

    test "stops for a time, and starts again", context do
      routine = start!(context)
      {view, _html} = open(context.conn, context.path)

      {view, _html} = press(view, context.conn, "pause", routine.id)
      assert has_element?(view, "[data-state=none]", "Paused")
      refute has_element?(view, "button[phx-click=pause]")
      assert {:ok, []} = Tasks.day(context.tomorrow, context.options)

      {view, _html} = press(view, context.conn, "resume", routine.id)
      assert has_element?(view, "[data-state=ok]", "Active")
      assert {:ok, [_morning, _evening]} = Tasks.day(context.tomorrow, context.options)
    end

    test "ends, with its tasks that come", context do
      routine = start!(context)
      {view, _html} = open(context.conn, context.path)

      {_view, html} = submit(view, context.conn, "#end-#{routine.id}", %{})

      assert html =~ "There is no routine yet."
      assert {:ok, []} = Tasks.day(context.tomorrow, context.options)
    end

    test "does nothing for a routine that is not on the page", context do
      start!(context)
      {view, _html} = open(context.conn, context.path)

      render_click(view, "pause", %{"id" => Ash.UUID.generate()})
      refute has_element?(view, "main p[role=alert]")
      assert has_element?(view, "[data-state=ok]", "Active")
    end

    test "is on the tasks page, which says that a task is from a routine", context do
      start!(context)

      {view, _html} =
        open(
          context.conn,
          ~p"/o/#{context.organisation.short_name}/tasks?day=#{Date.to_iso8601(context.tomorrow)}"
        )

      assert has_element?(view, "tbody td small", "From a routine")
      assert has_element?(view, "a", "Routines")
    end
  end

  describe "a routine for the doses of a prescription" do
    setup context do
      entry =
        Journal.write_entry!(
          %{
            resident_id: context.biscuit.id,
            kind: :prescription,
            medication: "A sample antibiotic",
            dose: "0.2 mL two times each day"
          },
          context.options
        )

      {:ok, %{prescription: prescription}} = Journal.entry_with_facts(entry.id, context.options)
      {:ok, prescription: prescription, entry: entry}
    end

    test "starts from the journal, with the resident and a title", context do
      journal = ~p"/o/#{context.organisation.short_name}/residents/#{context.biscuit.id}/journal"
      {view, _html} = open(context.conn, journal)

      {:ok, view, html} =
        view
        |> element("#dose-details-#{context.entry.id} a", "Plan the doses as a routine")
        |> render_click()
        |> follow_redirect(context.conn)

      assert html =~ "Each task of this routine writes a dose of A sample antibiotic"
      assert has_element?(view, "#new-routine[open]")
      assert has_element?(view, "#routine_title[value='Medicate: A sample antibiotic']")
      assert has_element?(view, "#routine_resident_id option[selected]", "Biscuit")

      {view, _html} =
        submit(view, context.conn, "#routine",
          routine: %{time_1: "08:00", time_2: "20:00", ends_on: Date.to_iso8601(context.tomorrow)}
        )

      assert has_element?(view, "tbody td small", "Writes a dose to the journal")

      {:ok, [routine]} = Tasks.routines(context.options)
      assert routine.prescription_id == context.prescription.id

      {:ok, tasks} = Tasks.day(context.tomorrow, context.options)
      assert [context.prescription.id] == tasks |> Enum.map(& &1.prescription_id) |> Enum.uniq()
    end

    test "is a plain routine when the prescription of the address is not there", context do
      for id <- [Ash.UUID.generate(), "not-an-id"] do
        {view, html} = open(context.conn, context.path <> "?prescription=#{id}")

        refute html =~ "writes a dose"
        refute has_element?(view, "#new-routine[open]")
      end
    end
  end

  describe "the words of a routine" do
    test "say when it repeats" do
      routine = fn facts -> Map.merge(%{pattern: :daily, every: nil, weekdays: []}, facts) end

      assert TaskWords.pattern(routine.(%{})) == "Each day"
      assert TaskWords.pattern(routine.(%{pattern: :weekly, weekdays: [6]})) == "Each Saturday"

      assert TaskWords.pattern(routine.(%{pattern: :weekly, weekdays: [1, 3, 5]})) ==
               "Each Monday, Wednesday and Friday"

      assert TaskWords.pattern(routine.(%{pattern: :interval, every: 1})) == "Each day"
      assert TaskWords.pattern(routine.(%{pattern: :interval, every: 3})) == "Every 3 days"
      assert TaskWords.pattern(routine.(%{pattern: :monthly, every: 1})) == "Each month"
      assert TaskWords.pattern(routine.(%{pattern: :monthly, every: 12})) == "Every 12 months"

      assert TaskWords.times([~T[08:00:00]]) == "08:00"

      assert TaskWords.times([~T[08:00:00], ~T[12:30:00], ~T[18:00:00]]) ==
               "08:00, 12:30 and 18:00"

      assert TaskWords.span(%{starts_on: ~D[2026-11-16], ends_on: nil}) == "From 16 November 2026"

      assert TaskWords.span(%{starts_on: ~D[2026-11-16], ends_on: ~D[2026-11-22]}) ==
               "From 16 November 2026 to 22 November 2026"

      assert TaskWords.days(1) == "1 day"
      assert TaskWords.days(14) == "14 days"
    end

    test "are there for each pattern, and the page offers each one" do
      assert Enum.sort(TaskWords.patterns()) == Enum.sort(Rescord.Tasks.RoutinePattern.values())

      assert Enum.map(TaskWords.pattern_options(), &elem(&1, 1)) ==
               ~w(daily weekly interval monthly)
    end
  end
end
