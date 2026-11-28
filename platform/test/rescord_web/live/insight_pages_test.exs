defmodule RescordWeb.InsightPagesTest do
  @moduledoc """
  Holds the pages of insights (ADR 0116): the list of them, and the care
  of the organisation day by day, a calendar of the tasks done on time and
  the tasks of the next two weeks.

  The tests find what a person finds: the region of a chart by its
  heading, the table by its caption, a link by its name (ADR 0107).

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [element: 2, render_click: 1, render_click: 3]

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Journal, Tasks}
  alias RescordWeb.Locale

  doctest RescordWeb.InsightWords

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    today = Accounts.today(organisation)

    {:ok,
     root: root,
     organisation: organisation,
     member: member,
     administrator: administrator,
     lists: lists,
     options: [actor: member, tenant: organisation],
     today: today,
     reports: ~p"/o/#{organisation.short_name}/reports",
     care: ~p"/o/#{organisation.short_name}/insights/care",
     conn: sign_in(context.conn, member)}
  end

  # An instant of a day in the organisation.
  defp at(context, date, time) do
    {:ok, instant} =
      Accounts.local_instant(context.organisation, "#{Date.to_iso8601(date)}T#{time}")

    instant
  end

  defp plan!(context, attributes) do
    Tasks.plan_task!(Map.merge(%{title: "Hay and pellets"}, attributes), context.options)
  end

  defp calendar, do: region("Tasks done on time")
  defp coming, do: region("The next two weeks")

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    build_conn() |> sign_in(outsider) |> visit(context.care) |> assert_path("/")
    build_conn() |> visit(context.care) |> assert_path("/")
  end

  test "the page of the reports has a card for each page of insights, in the Reports part",
       context do
    context.conn
    |> visit(context.reports)
    |> within(region("Insights"), &click_link(&1, "Care, day by day"))
    |> assert_path(context.care)
    |> assert_has("nav[aria-label=Site] a[aria-current]", text: "Reports")
    |> assert_has(navigation("Breadcrumb") |> link("Reports"))
  end

  describe "the care calendar" do
    test "has a day of tasks in words, and says the share done on time", context do
      yesterday = Date.add(context.today, -1)
      late = plan!(context, %{due_at: at(context, yesterday, "06:00")})
      {:ok, _} = Tasks.complete_task(late, %{}, context.options)
      skipped = plan!(context, %{due_at: at(context, yesterday, "07:00")})
      {:ok, _} = Tasks.skip_task(skipped, %{skip_reason: "No hay"}, context.options)

      context.conn
      |> visit(context.care)
      |> assert_has(heading("Care, day by day", level: 1))
      |> assert_has(calendar() |> table(~r/0% of 2 tasks were done on time/))
      |> assert_has(calendar(), text: "0 of 2 on time, 1 late, 1 skipped")
      |> assert_has(calendar(),
        text: "Week of #{Locale.date(Date.beginning_of_week(context.today))}"
      )
    end

    test "says the counts of a day that the person presses, with a link to its tasks",
         context do
      yesterday = Date.add(context.today, -1)
      task = plan!(context, %{due_at: at(context, yesterday, "06:00")})
      {:ok, _} = Tasks.skip_task(task, %{skip_reason: "No hay"}, context.options)

      context.conn
      |> visit(context.care)
      |> unwrap(fn view ->
        view |> element("td[phx-value-cell='#{Date.to_iso8601(yesterday)}']") |> render_click()
      end)
      |> assert_has(status(), text: Locale.day(yesterday))
      |> assert_has(status(), text: "0 of 1 on time, 1 skipped.")
      |> click_link("Open the tasks of this day")
      |> assert_path(~p"/o/#{context.organisation.short_name}/tasks",
        query_params: %{day: Date.to_iso8601(yesterday)}
      )
    end

    test "ignores a press on a day to come, or on what is no day", context do
      context.conn
      |> visit(context.care)
      |> unwrap(&render_click(&1, "pick", %{"cell" => "not a day"}))
      |> unwrap(fn view ->
        render_click(view, "pick", %{
          "cell" => Date.to_iso8601(Date.add(context.today, 3))
        })
      end)
      |> refute_has(status())
    end

    test "counts only the tasks of a kind that the person chooses", context do
      yesterday = Date.add(context.today, -1)

      plan!(context, %{
        due_at: at(context, yesterday, "06:00"),
        kind_id: context.lists.task_kind.feed
      })

      plan!(context, %{due_at: at(context, yesterday, "07:00")})

      context.conn
      |> visit(context.care)
      |> assert_has(calendar(), text: "0 of 2 on time, 2 overdue")
      |> select("Kind of task", option: "Feed")
      |> assert_has(calendar(), text: "0 of 1 on time, 1 overdue")
      |> refute_has(calendar(), text: "0 of 2 on time")
    end
  end

  describe "the next two weeks" do
    test "has the tasks of each day to come, and the busiest day in words", context do
      tomorrow = Date.add(context.today, 1)
      plan!(context, %{due_at: at(context, tomorrow, "08:00")})
      plan!(context, %{due_at: at(context, tomorrow, "18:00")})
      plan!(context, %{due_at: at(context, Date.add(context.today, 2), "08:00")})

      context.conn
      |> visit(context.care)
      |> assert_has(coming() |> table(~r/3 tasks are due in the next 14 days/))
      |> assert_has(coming(), text: "#{Locale.day(tomorrow)} has the most, 2 tasks.")
      |> assert_has(coming(),
        text: "Week of #{Locale.date(Date.beginning_of_week(Date.add(context.today, 14)))}"
      )
    end

    test "says when there is no task to come", context do
      context.conn
      |> visit(context.care)
      |> assert_has(coming(), text: "No task is due in the next 14 days.")
    end
  end

  describe "residents in care (ADR 0118)" do
    setup context do
      admin = [actor: context.administrator, tenant: context.organisation]
      Rescord.Locations.add_location!(%{name: "Hutch row", capacity: 1}, admin)

      biscuit =
        resident!(context.lists, context.options, %{arrived_on: Date.add(context.today, -20)})

      sage =
        resident!(context.lists, context.options, %{
          name: "Sage",
          arrived_on: Date.add(context.today, -10),
          species_id: context.lists.species.rabbit
        })

      {:ok, _} =
        Rescord.Residents.record_departure(
          %{resident_id: biscuit.id, kind: :release, departed_on: Date.add(context.today, -2)},
          context.options
        )

      {:ok, sage: sage, residents: ~p"/o/#{context.organisation.short_name}/insights/residents"}
    end

    test "has the figures, the line against the room, and the counts of each week", context do
      context.conn
      |> visit(context.residents)
      |> assert_has(heading("Residents in care", level: 1))
      |> assert_has(main(), text: "In care today 1 room for 1")
      |> assert_has(main(), text: "Arrivals 2 in 12 months")
      |> assert_has(main(), text: "Days over room 8 in 12 months")
      |> assert_has(
        region("Residents in care each day"),
        text:
          "1 resident is in care today, and the housing has room for 1. It had more than 1 on 8 days of the last 12 months, the first on #{Locale.date(Date.add(context.today, -10))}."
      )
      |> assert_has(region("Arrivals and departures"), text: "2 arrivals and 1 departure")
      |> assert_has(
        region("Arrivals and departures") |> table(~r/arrivals and departures/),
        text: Locale.date(Date.beginning_of_week(context.today))
      )
    end

    test "narrows to a species, but not the room", context do
      context.conn
      |> visit(context.residents)
      |> select("Species", option: "Rabbit")
      |> assert_has(main(), text: "Arrivals 1 in 12 months")
      |> assert_has(main(), text: "Days over room 0")
    end
  end

  describe "conditions by week (ADR 0119)" do
    setup context do
      diagnose = fn resident, onset_on ->
        Journal.write_entry!(
          %{
            resident_id: resident.id,
            kind: :diagnosis,
            condition_id: context.lists.condition.respiratory_infection,
            onset_on: onset_on
          },
          context.options
        )
      end

      sage = resident!(context.lists, context.options, %{name: "Sage"})

      pip =
        resident!(context.lists, context.options, %{
          name: "Pip",
          arrived_on: Date.add(context.today, -30)
        })

      diagnose.(resident!(context.lists, context.options), context.today)
      diagnose.(sage, context.today)
      diagnose.(pip, Date.add(context.today, -21))

      {:ok, conditions: ~p"/o/#{context.organisation.short_name}/insights/conditions"}
    end

    test "has the new cases of each week, the cases that go on, and the most in words",
         context do
      monday = Date.beginning_of_week(context.today)

      context.conn
      |> visit(context.conditions)
      |> assert_has(heading("Conditions by week", level: 1))
      |> assert_has(
        region("New cases of each condition") |> table(~r/3 new cases in the last 12 weeks/),
        text: "Respiratory infection 0 0 0 0 0 0 0 0 1 0 0 2 3"
      )
      |> assert_has(region("New cases of each condition"),
        text:
          "3 new cases in the last 12 weeks, and 3 cases go on now. The most in one week was 2 new cases of Respiratory infection, in the week of #{Locale.date(monday)}."
      )
    end

    test "the reports link to it", context do
      context.conn
      |> visit(context.reports)
      |> within(region("Insights"), &click_link(&1, "Conditions by week"))
      |> assert_path(context.conditions)
    end
  end

  test "the conditions by week say when there is no case", context do
    context.conn
    |> visit(~p"/o/#{context.organisation.short_name}/insights/conditions")
    |> assert_has(region("New cases of each condition"),
      text: "No condition started in the last 12 weeks, and none goes on now."
    )
  end

  describe "when the care is done (ADR 0120)" do
    test "has the tasks done in each hour, and the hours that slip", context do
      task = plan!(context, %{due_at: at(context, Date.add(context.today, -1), "08:00")})
      {:ok, done} = Tasks.complete_task(task, %{}, context.options)
      finished = Accounts.local_time(context.organisation, done.finished_at)

      context.conn
      |> visit(~p"/o/#{context.organisation.short_name}/insights/hours")
      |> assert_has(heading("When the care is done", level: 1))
      |> assert_has(region("Tasks done in each hour") |> table(~r/1 task was done/),
        text: "Monday"
      )
      |> assert_has(region("Tasks done in each hour"),
        text:
          "1 task was done in the last 12 weeks. The busiest hour was #{Locale.weekday(DateTime.to_date(finished))} from #{Locale.time(Time.new!(finished.hour, 0, 0))}, with 1 task done."
      )
      |> assert_has(region("Hours that slip"),
        text:
          "100% of the tasks done were done more than an hour after their time. The hour from #{Locale.time(~T[08:00:00])} slipped the most: 1 of 1 task late."
      )
    end

    test "says when no task was done", context do
      context.conn
      |> visit(~p"/o/#{context.organisation.short_name}/insights/hours")
      |> assert_has(region("Tasks done in each hour"),
        text: "No task was done in the last 12 weeks."
      )
      |> assert_has(region("Hours that slip"), text: "No task was done, so no hour slipped.")
    end
  end

  describe "stays (ADR 0121)" do
    test "has a row for each stay of the year, with its words, in the order chosen", context do
      biscuit =
        resident!(context.lists, context.options, %{
          name: "Biscuit",
          arrived_on: Date.add(context.today, -20)
        })

      resident!(context.lists, context.options, %{
        name: "Sage",
        arrived_on: Date.add(context.today, -10)
      })

      {:ok, _} =
        Rescord.Residents.record_departure(
          %{resident_id: biscuit.id, kind: :release, departed_on: Date.add(context.today, -15)},
          context.options
        )

      gone =
        resident!(context.lists, context.options, %{
          name: "Gone",
          arrived_on: Date.add(context.today, -500)
        })

      {:ok, _} =
        Rescord.Residents.record_departure(
          %{resident_id: gone.id, kind: :release, departed_on: Date.add(context.today, -400)},
          context.options
        )

      session =
        context.conn
        |> visit(~p"/o/#{context.organisation.short_name}/insights/stays")
        |> assert_has(heading("Stays", level: 1))
        |> assert_has(list("The stays") |> link("Biscuit"))
        |> assert_has(list("The stays") |> link("Sage"))
        |> refute_has(list("The stays") |> link("Gone"))
        |> assert_has(list("The stays"),
          text:
            "Surrender by an owner, #{Locale.date(Date.add(context.today, -20))} to #{Locale.date(Date.add(context.today, -15))}, 5 days, Release"
        )
        |> assert_has(region("The stays of the last 12 months"),
          text:
            "2 residents were in care in the last 12 months, and 1 stay goes on. The longest that goes on is of Sage: 10 days."
        )

      assert ["Biscuit", "Sage"] = names(session, list("The stays") |> link(nil))

      session
      |> select("Order", option: "Length, the longest first")
      |> then(&assert ["Sage", "Biscuit"] = names(&1, list("The stays") |> link(nil)))
    end
  end

  describe "medication courses (ADR 0122)" do
    test "has a row for each course of the three weeks, with its doses in words", context do
      today = context.today

      biscuit =
        resident!(context.lists, context.options, %{
          name: "Biscuit",
          arrived_on: Date.add(today, -40)
        })

      sage =
        resident!(context.lists, context.options, %{
          name: "Sage",
          arrived_on: Date.add(today, -40)
        })

      write = fn resident, facts ->
        entry = Journal.write_entry!(Map.put(facts, :resident_id, resident.id), context.options)
        {:ok, with_facts} = Journal.entry_with_facts(entry.id, context.options)
        with_facts
      end

      meloxicam =
        write.(biscuit, %{
          kind: :prescription,
          medication: "Meloxicam",
          dose: "0.2 mL each day",
          route: :oral,
          starts_on: Date.add(today, -5),
          ends_on: Date.add(today, 2)
        })

      write.(biscuit, %{
        kind: :prescription,
        medication: "Old drops",
        starts_on: Date.add(today, -40),
        ends_on: Date.add(today, -30)
      })

      write.(sage, %{kind: :prescription, medication: "Eye ointment"})

      write.(biscuit, %{
        kind: :dose,
        prescription_id: meloxicam.prescription.id,
        happened_at: DateTime.add(DateTime.utc_now(), -1, :day)
      })

      task =
        Tasks.plan_task!(
          %{
            title: "Meloxicam",
            due_at: at(context, Date.add(today, -2), "08:00"),
            prescription_id: meloxicam.prescription.id
          },
          context.options
        )

      {:ok, _} = Tasks.skip_task(task, %{skip_reason: "Would not take it"}, context.options)

      context.conn
      |> visit(~p"/o/#{context.organisation.short_name}/insights/medication")
      |> assert_has(heading("Medication courses", level: 1))
      |> assert_has(list("The courses") |> link("Meloxicam for Biscuit"))
      |> assert_has(list("The courses") |> link("Eye ointment for Sage"))
      |> refute_has(list("The courses") |> link("Old drops for Biscuit"))
      |> assert_has(list("The courses"),
        text:
          "0.2 mL each day, by mouth, #{Locale.date(Date.add(today, -5))} to #{Locale.date(Date.add(today, 2))}. 1 dose given, 1 dose due and not given in these weeks."
      )
      |> assert_has(list("The courses"),
        text: "from #{Locale.date(today)}, with no last day. No dose given in these weeks."
      )
      |> assert_has(region("Courses of three weeks"),
        text:
          "2 courses run in these three weeks, for 2 residents. 1 dose was given, and 1 dose was due and not given."
      )
    end
  end

  describe "stock and days left (ADR 0123)" do
    setup context do
      admin = [actor: context.administrator, tenant: context.organisation]
      shed = Rescord.Locations.add_location!(%{name: "Feed shed"}, admin)

      hay =
        Rescord.Inventory.add_item!(
          %{name: "Meadow hay", unit_id: context.lists.unit.bag, reorder_level: 2},
          admin
        )

      Rescord.Inventory.add_item!(%{name: "Aspen bedding"}, admin)

      lot =
        Rescord.Inventory.receive_lot!(
          %{
            item_id: hay.id,
            quantity: 10,
            location_id: shed.id,
            happened_at: DateTime.add(DateTime.utc_now(), -20, :day)
          },
          context.options
        )

      {:ok, _} =
        Rescord.Inventory.use_stock(
          %{lot_id: lot.id, location_id: shed.id, quantity: 6},
          context.options
        )

      {:ok, hay: hay}
    end

    test "the page has the days left of each item that was used", context do
      runs_out = Locale.date(Date.add(context.today, 20))

      context.conn
      |> visit(~p"/o/#{context.organisation.short_name}/insights/stock")
      |> assert_has(heading("Stock and days left", level: 1))
      |> assert_has(list("The items") |> link("Meadow hay"))
      |> assert_has(list("The items"),
        text:
          "4 bag in stock, and 6 bag used or discarded in 30 days: about 20 days left, to #{runs_out}."
      )
      |> assert_has(region("Days left of each item"),
        text:
          "1 item was used or discarded in the last 30 days, and 0 run out in the next 14 days at that rate. Meadow hay runs out first, on #{runs_out}."
      )
      |> assert_has(region("Days left of each item"),
        text: "With no use in the last 30 days: Aspen bedding."
      )
    end

    test "the page of an item has its stock over time", context do
      context.conn
      |> visit(~p"/o/#{context.organisation.short_name}/inventory/#{context.hay.id}")
      |> assert_has(region("Stock over time"),
        text:
          "4 bag in stock that has not expired. In the last 30 days, members used or discarded 6 bag, so it lasts about 20 more days, to #{Locale.date(Date.add(context.today, 20))}. The reorder level is 2 bag."
      )
    end
  end

  describe "lengths of stay (ADR 0124)" do
    test "has a line for each way of arrival with 10 stays or more, and the tables", context do
      for n <- 1..10 do
        resident =
          resident!(context.lists, context.options, %{
            name: "R#{n}",
            arrived_on: Date.add(context.today, -10)
          })

        if n <= 5 do
          {:ok, _} =
            Rescord.Residents.record_departure(
              %{
                resident_id: resident.id,
                kind: :release,
                departed_on: Date.add(context.today, -6)
              },
              context.options
            )
        end
      end

      resident!(context.lists, context.options, %{name: "Lone", arrival_kind: :stray})

      context.conn
      |> visit(~p"/o/#{context.organisation.short_name}/insights/lengths")
      |> assert_has(heading("Lengths of stay", level: 1))
      |> assert_has(region("Surrender by an owner"),
        text: "10 residents, and 5 in care now. Half had left by day 4."
      )
      |> assert_has(region("Stray"), text: "1 resident: too few for a line.")
      |> assert_has(table(~r/had left/) |> row(~r/^Surrender by an owner/),
        text: "Surrender by an owner 10 5 Day 4 Day 4 Not yet"
      )
      |> assert_has(table(~r/by how they ended/) |> row(~r/^Surrender by an owner/),
        text: "Surrender by an owner 0 5 0 5"
      )
    end

    test "says when no resident has arrived", context do
      context.conn
      |> visit(~p"/o/#{context.organisation.short_name}/insights/lengths")
      |> assert_has(main(), text: "No resident has arrived yet.")
    end
  end
end
