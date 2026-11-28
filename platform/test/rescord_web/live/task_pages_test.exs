defmodule RescordWeb.TaskPagesTest do
  @moduledoc """
  Holds the page of the tasks: the tasks of a day in the time zone of the
  organisation, their search and filters (ADR 0097), what a member does
  with a task, and a dose that a member plans from a prescription.

  The tests find what a person finds: the region "Tasks of the day", a
  row by its title, a button by its name (ADR 0107).

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest,
    only: [
      element: 2,
      render_change: 2,
      render_click: 3,
      render_submit: 3,
      assert_patch: 1,
      render_async: 1
    ]

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

  defp tasks, do: region("Tasks of the day")

  # The row of a task, by its title.
  defp task_row(title), do: tasks() |> row(~r/^#{Regex.escape(title)}\b/)

  # The titles of the tasks of the day, in the order of the page.
  defp titles(session), do: names(session, tasks() |> row(~r/./) |> link(~r/./))

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

    build_conn() |> sign_in(outsider) |> visit(context.path) |> assert_path("/")
    build_conn() |> visit(context.path) |> assert_path("/")
  end

  describe "the tasks of a day" do
    test "are the ones of today at first, with the time of the organisation", context do
      plan!(context, %{due_at: today_at(context, "23:30"), resident_ids: [context.biscuit.id]})

      plan!(context, %{
        title: "Tomorrow",
        due_at: DateTime.add(today_at(context, "23:30"), 1, :hour)
      })

      context.conn
      |> visit(context.path)
      |> assert_has(main(), text: "today")
      |> assert_has(task_row("Hay and pellets"), text: "11:30 pm Biscuit Anybody")
      |> refute_has(tasks(), text: "Tomorrow")
      |> click(link("The day after"))
      |> assert_has(task_row("Tomorrow"), text: "12:30 am")
      |> refute_has(tasks(), text: "Hay and pellets")
    end

    test "have the tasks of earlier days that are still due, on the page of today", context do
      {from, _to} = Accounts.day_range(context.organisation, context.today)
      plan!(context, %{title: "Nail trim", due_at: DateTime.add(from, -3, :hour)})
      done = plan!(context, %{title: "Old and done", due_at: DateTime.add(from, -4, :hour)})
      {:ok, _} = Tasks.complete_task(done, %{}, context.options)

      earlier = "The overdue tasks of earlier days come first"

      context.conn
      |> visit(context.path)
      |> assert_has(main(), text: earlier)
      # The task of an earlier day shows its day with its time.
      |> assert_has(task_row("Nail trim"), text: ResidentWords.date(Date.add(context.today, -1)))
      |> assert_has(task_row("Nail trim"), text: "Overdue")
      |> refute_has(tasks(), text: "Old and done")

      context.conn
      |> visit(context.path <> "?day=#{Date.add(context.today, 1)}")
      |> refute_has(main(), text: earlier)
      |> refute_has(tasks(), text: "Nail trim")
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
      at = fn query -> context.conn |> visit(context.path <> query) |> titles() end

      assert at.("") == ["Clean the hutch", "Hay and pellets", "Weigh Biscuit", "Fresh water"]
      assert at.("?who=me") == ["Clean the hutch"]
      assert at.("?who=anybody") == ["Weigh Biscuit", "Fresh water"]
      assert at.("?who=#{context.other.id}") == ["Hay and pellets"]
      assert at.("?state=done") == ["Fresh water"]
      assert at.("?state=due&who=anybody") == ["Weigh Biscuit"]
      assert at.("?kind_id=#{context.lists.task_kind.clean}") == ["Clean the hutch"]
      assert at.("?search=HAY") == ["Hay and pellets"]
    end

    test "a search by its label narrows the list", context do
      session =
        context.conn
        |> visit(context.path)
        |> within(tasks(), &fill_in(&1, "Search", with: "hay"))

      assert titles(session) == ["Hay and pellets"]
    end

    test "change the address, and a value that is no choice changes nothing", context do
      # The form of the filters is Cinder's own (ADR 0107).
      session =
        context.conn
        |> visit(context.path)
        |> unwrap(fn view ->
          view
          |> element("#tasks-filter-form")
          |> render_change(%{"filters" => %{"state" => "done"}})

          assert_patch(view)
          render_async(view)
        end)

      assert titles(session) == ["Fresh water"]

      session = context.conn |> visit(context.path <> "?who=nobody-at-all&state=lost")
      assert length(titles(session)) == 4
    end

    test "say when nothing matches, apart from a day with no task", context do
      context.conn
      |> visit(context.path <> "?search=nothing+like+this")
      |> assert_has(tasks(), text: "No task matches the search and the filters.")

      context.conn
      |> visit(context.path <> "?day=#{Date.add(context.today, 3)}")
      |> assert_has(tasks(), text: "There is no task on this day.")
    end

    test "stay on the links to another day, from its first page", context do
      session = visit(context.conn, context.path <> "?who=me&state=due&page=2")
      [href] = session |> one(link("The day after")) |> LazyHTML.attribute("href")

      query = URI.decode_query(URI.parse(href).query)
      assert query["who"] == "me"
      assert query["state"] == "due"
      assert query["day"] == Date.to_iso8601(Date.add(context.today, 1))
      refute Map.has_key?(query, "page")
    end

    test "stay after a member completes a task", context do
      session = visit(context.conn, context.path <> "?state=due")
      assert "Weigh Biscuit" in titles(session)

      session = click(session, tasks() |> button("Mark the task Weigh Biscuit as done"))

      refute "Weigh Biscuit" in titles(session)
      assert {:ok, %{state: :done}} = Tasks.task(context.open.id, context.options)
    end

    test "a page acts only on a task of its own day", context do
      later =
        plan!(context, %{
          title: "Later",
          due_at: DateTime.add(today_at(context, "12:00"), 3, :day)
        })

      # Events that the page does not offer: forged on purpose (ADR 0107).
      context.conn
      |> visit(context.path)
      |> unwrap(&render_click(&1, "complete", %{"id" => later.id}))
      |> unwrap(&render_click(&1, "complete", %{"id" => "not an id"}))
      |> refute_has(main() |> alert())

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
      title = context.task.title

      context.conn
      |> visit(context.day_path)
      |> click(tasks() |> button("Take the task #{title}"))
      |> assert_has(task_row(title), text: to_string(context.member.email))
      # The member has it, so the page does not offer it to them again.
      |> refute_has(tasks() |> button("Take the task #{title}"))
      |> click(tasks() |> button("Mark the task #{title} as done"))
      |> within(task_row(title), &assert_has(&1, "[data-state=ok]", text: "Done"))
      |> refute_has(tasks() |> button("Mark the task #{title} as done"))
      |> click(tasks() |> button("Open again the task #{title}"))
      |> within(task_row(title), &assert_has(&1, "[data-state=info]", text: "Due"))
    end

    test "is skipped with a reason", context do
      title = context.task.title

      context.conn
      |> visit(context.day_path)
      |> within(task_row(title), fn session ->
        session
        |> fill_in("Why you skip #{title}", with: "The clinic has her today")
        |> click_button("Skip the task")
      end)
      |> within(task_row(title), &assert_has(&1, "[data-state=none]", text: "Skipped"))
      |> assert_has(task_row(title), text: "Skipped: The clinic has her today")
    end

    test "says so when another member finished the task a moment before", context do
      # The page has not read again yet (ADR 0096): the two presses are in
      # the same moment.
      session = with_slow_changes(fn -> visit(context.conn, context.day_path) end)

      other = [actor: context.other, tenant: context.organisation]
      {:ok, _done} = Tasks.complete_task(context.task, %{}, other)

      session
      |> click(tasks() |> button("Mark the task #{context.task.title} as done"))
      |> assert_has(main() |> alert(), text: "Somebody changed this a moment ago")
      # The page shows the task as it is now.
      |> within(task_row(context.task.title), &assert_has(&1, "[data-state=ok]", text: "Done"))
      |> refute_has(main(), text: "Rescord.Tasks")
    end

    test "does nothing for a task that is not on the page", context do
      # An event that the page does not offer: forged on purpose (ADR 0107).
      context.conn
      |> visit(context.day_path)
      |> unwrap(&render_click(&1, "complete", %{"id" => Ash.UUID.generate()}))
      |> refute_has(main() |> alert())

      assert {:ok, %{state: :due}} = Tasks.task(context.task.id, context.options)
    end
  end

  describe "a new task" do
    test "is for a day and a time of the organisation, which can be months ahead", context do
      later = Date.add(context.today, 120)

      context.conn
      |> visit(context.path)
      |> fill_in("What to do", with: "Yearly check")
      |> fill_in("Day", with: Date.to_iso8601(later))
      |> fill_in("Time", with: "09:15")
      |> select("For a resident", option: "Biscuit")
      |> check(to_string(context.other.email))
      |> select("Kind", option: "Clean")
      |> click_button("Plan the task")
      # The page of that day.
      |> assert_has(main(), text: RescordWeb.TaskWords.day(later))
      |> assert_has(task_row("Yearly check"), text: "9:15 am")
      |> assert_has(task_row("Yearly check"), text: to_string(context.other.email))
      |> assert_has(task_row("Yearly check"), text: "Clean")

      {:ok, [task]} = Tasks.day(later, context.options)
      {:ok, expected} = Accounts.local_instant(context.organisation, "#{later}T09:15")
      assert DateTime.compare(task.due_at, expected) == :eq
    end

    test "reads a field that is not text, from a forged event, as no value", context do
      context.conn
      |> visit(context.path)
      |> unwrap(
        &render_submit(&1, "plan", %{
          "task" => %{
            "title" => ["a list"],
            "note" => %{"a" => "map"},
            "assignee_ids" => %{"a" => "map"},
            "date" => Date.to_iso8601(context.today),
            "time" => "09:15"
          }
        })
      )
      # The page is still there, and it says that the title is required.
      |> assert_has(main() |> alert(), text: "Title is required")

      assert {:ok, []} = Tasks.day(context.today, context.options)
    end

    test "says what is wrong, and keeps what the member typed", context do
      context.conn
      |> visit(context.path)
      |> fill_in("What to do", with: "A task")
      |> fill_in("Day", with: "")
      |> fill_in("Time", with: "09:15")
      |> click_button("Plan the task")
      |> assert_has(main() |> alert(), text: "The time is not a date and a time")
      |> assert_has("input", label: "What to do", value: "A task")
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

      journal = ~p"/o/#{context.organisation.short_name}/residents/#{context.biscuit.id}/journal"

      # Each entry of the journal has a form of its own, with the same labels.
      [entry] = elem(Journal.entries(context.biscuit.id, context.options), 1)

      context.conn
      |> visit(journal)
      |> within("#plan-dose-#{entry.id}", fn session ->
        session
        |> fill_in("Day", with: Date.to_iso8601(context.today))
        |> fill_in("Time", with: "23:45")
        |> click_button("Plan the dose")
      end)
      |> assert_has(status(), text: "The dose is in the tasks of that day.")

      {:ok, [task]} = Tasks.day(context.today, context.options)
      assert task.title == "Medicate: A sample antibiotic"
      assert Tasks.subject_names(task) == ["Biscuit"]

      build_conn()
      |> sign_in(context.other)
      |> visit(context.path)
      |> click(tasks() |> button("Mark the task #{task.title} as done"))

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
      session =
        context.conn
        |> visit(context.path)
        |> refute_has(tasks(), text: "Hay and pellets")

      other = [actor: context.other, tenant: context.organisation]
      task = plan!(context, %{due_at: today_at(context, "23:30")})

      session =
        session
        |> render_changes()
        |> assert_has(task_row("Hay and pellets"), text: "Anybody")

      taken = Tasks.take_task!(task, other)

      session =
        session
        |> render_changes()
        |> assert_has(task_row("Hay and pellets"), text: to_string(context.other.email))

      Tasks.complete_task!(taken, %{}, other)

      session
      |> render_changes()
      |> within(task_row("Hay and pellets"), &assert_has(&1, "[data-state=ok]", text: "Done"))
    end

    test "does not show a task of another organisation", context do
      session = visit(context.conn, context.path)

      elsewhere = organisation!(context.root, "Ironbark Flat")
      {_, stranger} = member!(elsewhere, :administrator, context.root)

      Tasks.plan_task!(
        %{title: "A task of Ironbark Flat", due_at: today_at(context, "23:30")},
        actor: stranger,
        tenant: elsewhere
      )

      session |> render_changes() |> refute_has(main(), text: "Ironbark Flat")
    end
  end
end
