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

  alias Rescord.{Accounts, Tasks}
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
end
