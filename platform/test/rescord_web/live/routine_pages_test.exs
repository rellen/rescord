defmodule RescordWeb.RoutinePagesTest do
  @moduledoc """
  Holds the page of the routines: what an administrator and a member read
  of a routine, the form
  of a new routine and of a change, the pause and the end of a routine, a
  routine for the doses of a prescription, and the words of a pattern. The page tests find what a person
  finds (ADR 0107).

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_async: 1, render_click: 3, render_submit: 3]
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
    # Only an administrator starts and changes a routine (ADR 0039).
    options = [actor: administrator, tenant: organisation]
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
     conn: sign_in(context.conn, administrator)}
  end

  defp routines, do: main() |> region("The routines")
  defp routine(title), do: routines() |> row(~r/^#{title}\b/)
  defp new_routine, do: main() |> details("New routine")

  defp visit_as(user, path), do: build_conn() |> sign_in(user) |> visit(path)

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

    outsider |> visit_as(context.path) |> assert_path("/")
    build_conn() |> visit(context.path) |> assert_path("/")
  end

  describe "the routines" do
    test "are on the page with when each repeats, what it is for, and its next task", context do
      start!(context, %{
        kind_id: context.lists.task_kind.feed,
        resident_ids: [context.biscuit.id],
        assignee_ids: [context.member.id, context.administrator.id],
        note: "Two scoops"
      })

      context.conn
      |> visit(context.path)
      |> assert_has(main(), text: "Rescord makes the tasks of a routine 14 days ahead.")
      |> assert_has(routine("Hay and pellets"), text: "Hay and pellets Feed Two scoops")
      |> assert_has(routine("Hay and pellets"), text: "Each day, at 8:00 am and 6:00 pm")
      |> assert_has(routine("Hay and pellets"), text: "Biscuit")
      |> assert_has(routine("Hay and pellets"),
        text: "#{context.member.email}, #{context.administrator.email}"
      )
      |> assert_has(routine("Hay and pellets"), state: "ok", text: "Active")
      |> assert_has(routine("Hay and pellets"), text: "Next:")
    end

    test "are on the page of a member, who changes none of them", context do
      start!(context)

      context.member
      |> visit_as(context.path)
      |> assert_has(routine("Hay and pellets"))
      |> refute_has(new_routine())
      |> refute_has(routines() |> link("Change the routine Hay and pellets"))
      |> refute_has(routines() |> button(~r/./))
      |> refute_has(routines() |> details(~r/./))
    end

    test "say so when there is none", context do
      context.conn |> visit(context.path) |> assert_has(routines(), text: "No routine yet.")
    end

    test "say when one has not started, and when one is finished", context do
      start!(context, %{title: "Later", starts_on: Date.add(context.today, 5)})
      routine = start!(context, %{title: "Short"})

      # The last day of the routine was yesterday.
      Ash.Seed.update!(routine, %{
        starts_on: Date.add(context.today, -3),
        ends_on: Date.add(context.today, -1)
      })

      context.conn
      |> visit(context.path)
      |> assert_has(routine("Later"), state: "info", text: "Not started")
      |> assert_has(routine("Short"), state: "none", text: "Finished")
    end
  end

  describe "a new routine" do
    test "starts with the facts of the form, and has its tasks", context do
      context.conn
      |> visit(context.path)
      |> fill_in("What to do", with: "Clean the water bottles")
      |> select("Kind", option: "Clean")
      |> fill_in("Time", with: "07:30")
      |> fill_in("A second time, if there is one", with: "17:00")
      |> fill_in("First day", with: Date.to_iso8601(context.tomorrow))
      |> select("For a resident", option: "Biscuit")
      |> click(button("Start the routine"))
      |> assert_has(routine("Clean the water bottles"), text: "Each day, at 7:30 am and 5:00 pm")

      {:ok, tasks} = Tasks.day(context.tomorrow, context.options)
      assert Enum.map(tasks, & &1.title) == List.duplicate("Clean the water bottles", 2)
      assert Tasks.subject_names(hd(tasks)) == ["Biscuit"]
    end

    test "asks for the days of the week, or for a number, when the pattern needs one", context do
      session = visit(context.conn, context.path)
      refute has?(session, new_routine() |> field("Monday"))
      refute has?(session, new_routine() |> field("Every how many days"))

      session = select(session, "How it repeats", option: "On given days of the week")
      assert has?(session, new_routine() |> field("Monday"))
      assert has?(session, new_routine() |> field("Sunday"))
      refute has?(session, new_routine() |> field("Every how many days"))

      session = select(session, "How it repeats", option: "Every number of days")
      refute has?(session, new_routine() |> field("Monday"))
      assert has?(session, new_routine() |> field("Every how many days"))

      session = select(session, "How it repeats", option: "Every number of months")
      assert has?(session, new_routine() |> field("Every how many months"))
    end

    test "counts from the last task, and is for the members that the form ticks", context do
      session = visit(context.conn, context.path)
      refute has?(session, new_routine() |> field("Count the days from"))

      session
      |> fill_in("What to do", with: "Weigh")
      |> select("How it repeats", option: "Every number of days")
      |> fill_in("Every how many days", with: "7")
      |> select("Count the days from", option: "The day when a member last finishes a task")
      |> check(to_string(context.member.email))
      |> check(to_string(context.administrator.email))
      |> fill_in("Time", with: "09:00")
      |> click(button("Start the routine"))
      |> assert_has(routine("Weigh"), text: "7 days after the last task is done")

      {:ok, [routine]} = Tasks.routines(context.options)
      assert routine.count_from == :last_done

      assert Enum.sort(routine.assignee_ids) ==
               Enum.sort([context.member.id, context.administrator.id])
    end

    test "is on given days of the week", context do
      context.conn
      |> visit(context.path)
      |> select("How it repeats", option: "On given days of the week")
      |> fill_in("What to do", with: "Weigh each resident")
      |> check("Monday")
      |> check("Thursday")
      |> fill_in("Time", with: "09:00")
      |> click(button("Start the routine"))
      |> assert_has(routine("Weigh each resident"), text: "Each Monday and Thursday, at 9:00 am")

      {:ok, [routine]} = Tasks.routines(context.options)
      assert %{pattern: :weekly, weekdays: [1, 4], times: [~T[09:00:00]]} = routine
    end

    test "is every number of months, a year ahead", context do
      context.conn
      |> visit(context.path)
      |> select("How it repeats", option: "Every number of months")
      |> fill_in("What to do", with: "Yearly check")
      |> fill_in("Every how many months", with: "12")
      |> fill_in("Time", with: "10:00")
      |> fill_in("Days ahead", with: "400")
      |> click(button("Start the routine"))
      |> assert_has(routine("Yearly check"), text: "Every 12 months, at 10:00 am")

      {:ok, [routine]} = Tasks.routines(context.options)
      assert %{pattern: :monthly, every: 12, days_ahead: 400} = routine
    end

    test "says what is wrong, and keeps what the member typed", context do
      session =
        context.conn
        |> visit(context.path)
        |> select("How it repeats", option: "On given days of the week")
        |> fill_in("What to do", with: "Weigh each resident")
        |> fill_in("Time", with: "09:00")
        |> click(button("Start the routine"))
        |> assert_has(new_routine() |> alert(),
          text: "Weekdays needs one day of the week or more"
        )

      assert value(session, new_routine() |> field("What to do")) == "Weigh each resident"
      assert has?(session, new_routine() |> field("Monday"))
      assert {:ok, []} = Tasks.routines(context.options)
    end

    test "does not take a pattern that the page did not offer", context do
      context.conn
      |> visit(context.path)
      |> unwrap(
        &render_submit(&1, "save", %{
          "routine" => %{
            "title" => "X",
            "pattern" => "hourly",
            "time_1" => "09:00",
            "starts_on" => Date.to_iso8601(context.today)
          }
        })
      )
      |> assert_has(main() |> alert())

      assert {:ok, []} = Tasks.routines(context.options)
    end
  end

  describe "a routine on the page" do
    test "is changed on its own page, which has its facts", context do
      routine = start!(context, %{resident_ids: [context.biscuit.id], note: "Two scoops"})
      change = main() |> region("Change the routine Hay and pellets")

      session =
        context.conn
        |> visit(context.path)
        |> click(routine("Hay and pellets") |> link("Change the routine Hay and pellets"))
        |> assert_path(context.path <> "/#{routine.id}/edit")

      assert value(session, change |> field("What to do")) == "Hay and pellets"
      assert value(session, change |> field("Time")) == "08:00"
      assert value(session, change |> field("A second time, if there is one")) == "18:00"
      assert value(session, change |> field("For a resident")) == "Biscuit"

      # The list and the form of a new routine are not on this page.
      session
      |> refute_has(new_routine())
      |> refute_has(routines())
      |> fill_in("What to do", with: "Hay only")
      |> fill_in("A second time, if there is one", with: "")
      |> click(button("Save the routine"))
      |> assert_has(routine("Hay only"), text: "Each day, at 8:00 am From")

      {:ok, tasks} = Tasks.day(context.tomorrow, context.options)
      assert Enum.map(tasks, & &1.title) == ["Hay only"]
    end

    test "goes to the list when the routine of the address is not there", context do
      context.conn
      |> visit(context.path <> "/#{Ash.UUID.generate()}/edit")
      |> assert_path(context.path)
    end

    test "stops for a time, and starts again", context do
      start!(context)

      session =
        context.conn
        |> visit(context.path)
        |> click(routine("Hay and pellets") |> button("Pause the routine Hay and pellets"))
        |> assert_has(routine("Hay and pellets"), state: "none", text: "Paused")
        |> refute_has(routine("Hay and pellets") |> button("Pause the routine Hay and pellets"))

      assert {:ok, []} = Tasks.day(context.tomorrow, context.options)

      session
      |> click(routine("Hay and pellets") |> button("Start again the routine Hay and pellets"))
      |> assert_has(routine("Hay and pellets"), state: "ok", text: "Active")

      assert {:ok, [_morning, _evening]} = Tasks.day(context.tomorrow, context.options)
    end

    test "ends, with its tasks that come", context do
      start!(context)

      context.conn
      |> visit(context.path)
      |> click(
        routine("Hay and pellets")
        |> details("End the routine Hay and pellets")
        |> button("End the routine Hay and pellets")
      )
      |> assert_has(routines(), text: "No routine yet.")

      assert {:ok, []} = Tasks.day(context.tomorrow, context.options)
    end

    test "does nothing for a routine that is not on the page", context do
      start!(context)

      context.conn
      |> visit(context.path)
      |> unwrap(&render_click(&1, "pause", %{"id" => Ash.UUID.generate()}))
      |> refute_has(main() |> alert())
      |> assert_has(routine("Hay and pellets"), state: "ok", text: "Active")
    end

    test "is on the tasks page, which says that a task is from a routine", context do
      start!(context)

      context.conn
      |> visit(
        ~p"/o/#{context.organisation.short_name}/tasks?day=#{Date.to_iso8601(context.tomorrow)}"
      )
      |> unwrap(&render_async/1)
      |> assert_has(main() |> row(~r/Hay and pellets/), text: "From a routine")
      |> assert_has(main() |> link("Routines"))
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

      {:ok,
       prescription: prescription,
       entry: entry,
       journal: ~p"/o/#{context.organisation.short_name}/residents/#{context.biscuit.id}/journal"}
    end

    test "is not offered on the journal of a member", context do
      context.member
      |> visit_as(context.journal)
      |> unwrap(&render_async/1)
      |> assert_has(main() |> details("Plan a dose"))
      |> refute_has(main() |> details("Plan a dose") |> link("Plan the doses as a routine"))
    end

    test "starts from the journal, with the resident and a title", context do
      session =
        context.conn
        |> visit(context.journal)
        |> unwrap(&render_async/1)
        |> click(main() |> details("Plan a dose") |> link("Plan the doses as a routine"))
        |> assert_has(new_routine(),
          text: "Each task of this routine writes a dose of A sample antibiotic"
        )

      assert open?(session, new_routine())

      assert value(session, new_routine() |> field("What to do")) ==
               "Medicate: A sample antibiotic"

      assert value(session, new_routine() |> field("For a resident")) == "Biscuit"

      session
      |> fill_in("Time", with: "08:00")
      |> fill_in("A second time, if there is one", with: "20:00")
      |> fill_in("Last day, if there is one", with: Date.to_iso8601(context.tomorrow))
      |> click(button("Start the routine"))
      |> assert_has(routine("Medicate: A sample antibiotic"),
        text: "Writes a dose to the journal"
      )

      {:ok, [routine]} = Tasks.routines(context.options)
      assert routine.prescription_id == context.prescription.id

      {:ok, tasks} = Tasks.day(context.tomorrow, context.options)
      assert [context.prescription.id] == tasks |> Enum.map(& &1.prescription_id) |> Enum.uniq()
    end

    test "is a plain routine when the prescription of the address is not there", context do
      for id <- [Ash.UUID.generate(), "not-an-id"] do
        session =
          context.conn
          |> visit(context.path <> "?prescription=#{id}")
          |> refute_has(main(), text: "writes a dose")

        refute open?(session, new_routine())
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

      assert TaskWords.pattern(routine.(%{pattern: :interval, every: 3, count_from: :last_done})) ==
               "3 days after the last task is done"

      assert TaskWords.pattern(routine.(%{pattern: :interval, every: 1, count_from: :last_done})) ==
               "1 day after the last task is done"

      assert TaskWords.pattern(routine.(%{pattern: :interval, every: 3, count_from: :first_day})) ==
               "Every 3 days"

      assert TaskWords.pattern(routine.(%{pattern: :monthly, every: 1})) == "Each month"
      assert TaskWords.pattern(routine.(%{pattern: :monthly, every: 12})) == "Every 12 months"

      assert TaskWords.times([~T[08:00:00]]) == "8:00 am"

      assert TaskWords.times([~T[08:00:00], ~T[12:30:00], ~T[18:00:00]]) ==
               "8:00 am, 12:30 pm and 6:00 pm"

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
