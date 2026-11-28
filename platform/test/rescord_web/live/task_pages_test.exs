defmodule RescordWeb.TaskPagesTest do
  @moduledoc """
  Holds the page of the tasks: the tasks of a day in the time zone of the
  organisation, their search and filters (ADR 0097), what a member does
  with a task, and a dose that a member plans from a prescription.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import RescordWeb.Roles
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Journal, Tasks}
  alias RescordWeb.ResidentWords

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    {_, other} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    today = Accounts.today(organisation)

    {:ok,
     root: root,
     organisation: organisation,
     member: member,
     other: other,
     lists: lists,
     options: options,
     today: today,
     biscuit: resident!(lists, options),
     path: ~p"/o/#{organisation.short_name}/tasks",
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

  # A press on a button of a task: the page stays, and the collection reads
  # again.
  defp press(view, event, id) do
    render_click(view, event, %{"id" => id})
    {view, render_async(view)}
  end

  # The rows of the collection, by the id of their task.
  defp rows(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#day-tasks tbody tr[data-item-id]")
    |> LazyHTML.attribute("data-item-id")
  end

  # A time of today in the organisation, as an instant.
  defp today_at(context, time) do
    {:ok, instant} =
      Accounts.local_instant(context.organisation, "#{Date.to_iso8601(context.today)}T#{time}")

    instant
  end

  defp plan!(context, attributes) do
    Tasks.plan_task!(Map.merge(%{title: "Hay and pellets"}, attributes), context.options)
  end

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    assert {:error, {:redirect, %{to: "/"}}} =
             build_conn() |> sign_in(outsider) |> live(context.path)

    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.path)
  end

  describe "the tasks of a day" do
    test "are the ones of today at first, with the time of the organisation", context do
      plan!(context, %{due_at: today_at(context, "23:30"), resident_ids: [context.biscuit.id]})

      plan!(context, %{
        title: "Tomorrow",
        due_at: DateTime.add(today_at(context, "23:30"), 1, :hour)
      })

      {view, html} = open(context.conn, context.path)

      assert html =~ "today"
      assert html =~ "Hay and pellets"
      assert has_element?(view, "tbody td", "11:30 pm")
      assert has_element?(view, "tbody td", "Biscuit")
      assert has_element?(view, "tbody td", "Anybody")
      refute html =~ "Tomorrow"

      view |> element("a", "The day after") |> render_click()
      html = render_async(view)
      assert html =~ "Tomorrow"
      assert has_element?(view, "tbody td", "12:30 am")
      refute html =~ "Hay and pellets"
    end

    test "have the tasks of earlier days that are still due, on the page of today", context do
      {from, _to} = Accounts.day_range(context.organisation, context.today)
      plan!(context, %{title: "Nail trim", due_at: DateTime.add(from, -3, :hour)})
      done = plan!(context, %{title: "Old and done", due_at: DateTime.add(from, -4, :hour)})
      {:ok, _} = Tasks.complete_task(done, %{}, context.options)

      {view, html} = open(context.conn, context.path)

      assert html =~ "The tasks of earlier days that are still due come first"
      assert html =~ "Nail trim"
      # The task of an earlier day shows its day with its time.
      assert has_element?(view, "tbody td", ResidentWords.date(Date.add(context.today, -1)))
      assert has_element?(view, "[data-state=alert]", "Overdue")
      refute html =~ "Old and done"

      {_view, html} = open(context.conn, context.path <> "?day=#{Date.add(context.today, 1)}")
      refute html =~ "The tasks of earlier days that are still due come first"
      refute html =~ "Nail trim"
    end
  end

  describe "the search and the filters (ADR 0097)" do
    setup context do
      mine =
        plan!(context, %{
          title: "Clean the hutch",
          due_at: today_at(context, "09:00"),
          assignee_ids: [context.member.id],
          kind_id: context.lists.task_kind.clean
        })

      theirs =
        plan!(context, %{
          title: "Hay and pellets",
          due_at: today_at(context, "10:00"),
          assignee_ids: [context.other.id]
        })

      open = plan!(context, %{title: "Weigh Biscuit", due_at: today_at(context, "11:00")})
      done = plan!(context, %{title: "Fresh water", due_at: today_at(context, "12:00")})
      {:ok, _done} = Tasks.complete_task(done, %{}, context.options)

      {:ok, mine: mine, theirs: theirs, open: open, done: done}
    end

    test "are in the address, so a link gives the same list", context do
      {view, _html} = open(context.conn, context.path)

      assert rows(view) ==
               Enum.map([context.mine, context.theirs, context.open, context.done], & &1.id)

      {view, _html} = open(context.conn, context.path <> "?who=me")
      assert rows(view) == [context.mine.id]

      {view, _html} = open(context.conn, context.path <> "?who=anybody")
      assert rows(view) == [context.open.id, context.done.id]

      {view, _html} = open(context.conn, context.path <> "?who=#{context.other.id}")
      assert rows(view) == [context.theirs.id]

      {view, _html} = open(context.conn, context.path <> "?state=done")
      assert rows(view) == [context.done.id]

      {view, _html} = open(context.conn, context.path <> "?state=due&who=anybody")
      assert rows(view) == [context.open.id]

      {view, _html} =
        open(context.conn, context.path <> "?kind_id=#{context.lists.task_kind.clean}")

      assert rows(view) == [context.mine.id]

      {view, _html} = open(context.conn, context.path <> "?search=HAY")
      assert rows(view) == [context.theirs.id]
    end

    test "change the address, and a value that is no choice changes nothing", context do
      {view, _html} = open(context.conn, context.path)

      view
      |> element("#tasks-filter-form")
      |> render_change(%{"filters" => %{"state" => "done"}})

      assert_patch(view)
      render_async(view)
      assert rows(view) == [context.done.id]

      {view, _html} = open(context.conn, context.path <> "?who=nobody-at-all&state=lost")
      assert length(rows(view)) == 4
    end

    test "say when nothing matches, apart from a day with no task", context do
      {_view, html} = open(context.conn, context.path <> "?search=nothing+like+this")
      assert html =~ "No task matches the search and the filters."

      {_view, html} = open(context.conn, context.path <> "?day=#{Date.add(context.today, 3)}")
      assert html =~ "There is no task on this day."
    end

    test "stay on the links to another day, from its first page", context do
      {view, _html} = open(context.conn, context.path <> "?who=me&state=due&page=2")

      href =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("a[data-variant=secondary]")
        |> Enum.find(&(LazyHTML.text(&1) =~ "The day after"))
        |> LazyHTML.attribute("href")
        |> hd()

      query = URI.decode_query(URI.parse(href).query)
      assert query["who"] == "me"
      assert query["state"] == "due"
      assert query["day"] == Date.to_iso8601(Date.add(context.today, 1))
      refute Map.has_key?(query, "page")
    end

    test "stay after a member completes a task", context do
      {view, _html} = open(context.conn, context.path <> "?state=due")
      assert context.open.id in rows(view)

      {view, _html} = press(view, "complete", context.open.id)

      refute context.open.id in rows(view)
      assert {:ok, %{state: :done}} = Tasks.task(context.open.id, context.options)
    end

    test "a page acts only on a task of its own day", context do
      later =
        plan!(context, %{
          title: "Later",
          due_at: DateTime.add(today_at(context, "12:00"), 3, :day)
        })

      {view, _html} = open(context.conn, context.path)

      render_click(view, "complete", %{"id" => later.id})
      render_click(view, "complete", %{"id" => "not an id"})

      refute has_element?(view, "main p[role=alert]")
      assert {:ok, %{state: :due}} = Tasks.task(later.id, context.options)
    end
  end

  describe "a task on the page" do
    setup context do
      task = plan!(context, %{due_at: DateTime.add(DateTime.utc_now(), 30, :minute)})
      date = Accounts.local_date(context.organisation, task.due_at)
      {:ok, task: task, day_path: context.path <> "?day=#{date}"}
    end

    test "is taken, done, and opened again", context do
      {view, _html} = open(context.conn, context.day_path)
      tasks = region("Tasks of the day")
      title = context.task.title

      click(view, tasks |> button("Take the task #{title}"))
      assert text(view, tasks) =~ to_string(context.member.email)
      # The member has it, so the page does not offer it to them again.
      refute has?(view, tasks |> button("Take the task #{title}"))

      click(view, tasks |> button("Mark the task #{title} as done"))
      assert has_element?(view, "[data-state=ok]", "Done")
      refute has?(view, tasks |> button("Mark the task #{title} as done"))

      click(view, tasks |> button("Open again the task #{title}"))
      assert has_element?(view, "[data-state=info]", "Due")
    end

    test "is skipped with a reason", context do
      {view, _html} = open(context.conn, context.day_path)

      view
      |> form("#skip-#{context.task.id}", skip: %{reason: "The clinic has her today"})
      |> render_submit()

      html = render_async(view)

      assert has_element?(view, "[data-state=none]", "Skipped")
      assert html =~ "Skipped: The clinic has her today"
    end

    test "says so when another member finished the task a moment before", context do
      # The page has not read again yet (ADR 0096): the two presses are in
      # the same moment.
      {view, _html} = with_slow_changes(fn -> open(context.conn, context.day_path) end)

      other = [actor: context.other, tenant: context.organisation]
      {:ok, _done} = Tasks.complete_task(context.task, %{}, other)

      render_click(view, "complete", %{"id" => context.task.id})
      html = render_async(view)

      assert has_element?(view, "main p[role=alert]", "Somebody changed this a moment ago")
      # The page shows the task as it is now.
      assert has_element?(view, "[data-state=ok]", "Done")
      refute html =~ "Rescord.Tasks"
    end

    test "does nothing for a task that is not on the page", context do
      {view, _html} = open(context.conn, context.day_path)

      render_click(view, "complete", %{"id" => Ash.UUID.generate()})
      refute has_element?(view, "main p[role=alert]")
      assert {:ok, %{state: :due}} = Tasks.task(context.task.id, context.options)
    end
  end

  describe "a new task" do
    test "is for a day and a time of the organisation, which can be months ahead", context do
      later = Date.add(context.today, 120)
      {view, _html} = open(context.conn, context.path)

      {view, html} =
        submit(view, context.conn, "#task",
          task: %{
            title: "Yearly check",
            date: Date.to_iso8601(later),
            time: "09:15",
            resident_id: context.biscuit.id,
            assignee_ids: [context.other.id],
            kind_id: context.lists.task_kind.clean
          }
        )

      # The page of that day.
      assert html =~ RescordWeb.TaskWords.day(later)
      assert html =~ "Yearly check"
      assert has_element?(view, "tbody td", "9:15 am")
      assert has_element?(view, "tbody td", to_string(context.other.email))
      assert has_element?(view, "tbody small", "Clean")

      {:ok, [task]} = Tasks.day(later, context.options)
      {:ok, expected} = Accounts.local_instant(context.organisation, "#{later}T09:15")
      assert DateTime.compare(task.due_at, expected) == :eq
    end

    test "reads a field that is not text, from a forged event, as no value", context do
      {view, _html} = open(context.conn, context.path)

      render_submit(view, "plan", %{
        "task" => %{
          "title" => ["a list"],
          "note" => %{"a" => "map"},
          "assignee_ids" => %{"a" => "map"},
          "date" => Date.to_iso8601(context.today),
          "time" => "09:15"
        }
      })

      # The page is still there, and it says that the title is required.
      assert has_element?(view, "main p[role=alert]", "Title is required")
      assert {:ok, []} = Tasks.day(context.today, context.options)
    end

    test "says what is wrong, and keeps what the member typed", context do
      {view, _html} = open(context.conn, context.path)

      html =
        view
        |> form("#task", task: %{title: "A task", date: "", time: "09:15"})
        |> render_submit()

      assert has_element?(view, "#new-task p[role=alert]", "The time is not a date and a time")
      assert html =~ ~s(value="A task")
    end
  end

  describe "a dose from the journal" do
    test "is a task, and the member who completes it writes the dose", context do
      Journal.write_entry!(
        %{
          resident_id: context.biscuit.id,
          kind: :prescription,
          medication: "A sample antibiotic",
          dose: "0.2 mL two times each day"
        },
        context.options
      )

      [entry] = elem(Journal.entries(context.biscuit.id, context.options), 1)
      journal = ~p"/o/#{context.organisation.short_name}/residents/#{context.biscuit.id}/journal"
      {view, _html} = open(context.conn, journal)

      {_view, html} =
        submit(view, context.conn, "#plan-dose-#{entry.id}",
          dose: %{date: Date.to_iso8601(context.today), time: "23:45"}
        )

      assert html =~ "The dose is in the tasks of that day."

      {:ok, [task]} = Tasks.day(context.today, context.options)
      assert task.title == "Medicate: A sample antibiotic"
      assert Tasks.subject_names(task) == ["Biscuit"]

      conn = build_conn() |> sign_in(context.other)
      {view, _html} = open(conn, context.path)
      {_view, _html} = press(view, "complete", task.id)

      {:ok, [dose, _prescription]} = Journal.entries(context.biscuit.id, context.options)
      assert dose.kind == :dose
      assert dose.author_id == context.other.id
    end
  end

  test "each phase of a task has a word and a kind of state" do
    assert Enum.sort(RescordWeb.TaskWords.phases()) == [:done, :due, :overdue, :skipped]

    for phase <- RescordWeb.TaskWords.phases() do
      assert is_binary(RescordWeb.TaskWords.phase(phase))
      assert RescordWeb.TaskWords.phase_kind(phase) in ~w(ok alert info none)
    end

    assert RescordWeb.TaskWords.day(~D[2026-11-16]) == "Monday, 16 November 2026"
  end

  describe "what another member does (ADR 0096)" do
    test "shows at once: a new task, who took it, and that it is done", context do
      {view, html} = open(context.conn, context.path)
      refute html =~ "Hay and pellets"

      other = [actor: context.other, tenant: context.organisation]
      task = plan!(context, %{due_at: today_at(context, "23:30")})
      row = "tr[data-item-id='#{task.id}']"
      assert render_changes(view) =~ "Hay and pellets"
      assert has_element?(view, "#{row} td", "Anybody")

      taken = Tasks.take_task!(task, other)
      render_changes(view)
      assert has_element?(view, "#{row} td", to_string(context.other.email))

      Tasks.complete_task!(taken, %{}, other)
      render_changes(view)
      assert has_element?(view, "#{row} [data-state=ok]", "Done")
    end

    test "does not show a task of another organisation", context do
      {view, _html} = open(context.conn, context.path)

      elsewhere = organisation!(context.root, "Ironbark Flat")
      {_, stranger} = member!(elsewhere, :administrator, context.root)

      Tasks.plan_task!(
        %{title: "A task of Ironbark Flat", due_at: today_at(context, "23:30")},
        actor: stranger,
        tenant: elsewhere
      )

      refute render_changes(view) =~ "Ironbark Flat"
    end
  end
end
