defmodule RescordWeb.TaskPagesTest do
  @moduledoc """
  Holds the page of the tasks: the tasks of a day in the time zone of the
  organisation, what a member does with a task, and a dose that a member
  plans from a prescription.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Journal, Tasks}

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

  defp press(view, conn, event, id) do
    {:ok, view, _html} = view |> render_click(event, %{"id" => id}) |> follow_redirect(conn)
    {view, render_async(view)}
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
      assert has_element?(view, "tbody td", "23:30")
      assert has_element?(view, "tbody td", "Biscuit")
      assert has_element?(view, "tbody td", "Anybody")
      refute html =~ "Tomorrow"

      html = view |> element("a", "The day after") |> render_click()
      assert html =~ "Tomorrow"
      assert has_element?(view, "tbody td", "00:30")
      refute html =~ "Hay and pellets"
    end

    test "have the tasks of earlier days that are still due, on the page of today", context do
      {from, _to} = Accounts.day_range(context.organisation, context.today)
      plan!(context, %{title: "Nail trim", due_at: DateTime.add(from, -3, :hour)})
      done = plan!(context, %{title: "Old and done", due_at: DateTime.add(from, -4, :hour)})
      {:ok, _} = Tasks.complete_task(done, %{}, context.options)

      {view, html} = open(context.conn, context.path)

      assert html =~ "Still due from earlier days"
      assert html =~ "Nail trim"
      assert has_element?(view, "[data-state=alert]", "Overdue")
      refute html =~ "Old and done"

      {_view, html} = open(context.conn, context.path <> "?day=#{Date.add(context.today, 1)}")
      refute html =~ "Still due from earlier days"
    end
  end

  describe "a task on the page" do
    setup context do
      task = plan!(context, %{due_at: DateTime.add(DateTime.utc_now(), 30, :minute)})
      date = Accounts.local_date(context.organisation, task.due_at)
      {:ok, task: task, day_path: context.path <> "?day=#{date}"}
    end

    test "is taken, done, and opened again", context do
      conn = context.conn
      {view, _html} = open(conn, context.day_path)

      {view, _html} = press(view, conn, "take", context.task.id)
      assert has_element?(view, "tbody td", to_string(context.member.email))
      # The member has it, so the page does not offer it to them again.
      refute has_element?(view, "button[phx-click=take]")

      {view, _html} = press(view, conn, "complete", context.task.id)
      assert has_element?(view, "[data-state=ok]", "Done")
      refute has_element?(view, "button[phx-click=complete]")

      {view, _html} = press(view, conn, "reopen", context.task.id)
      assert has_element?(view, "[data-state=info]", "Due")
    end

    test "is skipped with a reason", context do
      {view, _html} = open(context.conn, context.day_path)

      {view, html} =
        submit(view, context.conn, "#skip-#{context.task.id}",
          skip: %{reason: "The clinic has her today"}
        )

      assert has_element?(view, "[data-state=none]", "Skipped")
      assert html =~ "Skipped: The clinic has her today"
    end

    test "says so when another member finished the task a moment before", context do
      {view, _html} = open(context.conn, context.day_path)

      other = [actor: context.other, tenant: context.organisation]
      {:ok, _done} = Tasks.complete_task(context.task, %{}, other)

      html = render_click(view, "complete", %{"id" => context.task.id})

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
            assignee_id: context.other.id,
            kind_id: context.lists.task_kind.clean
          }
        )

      # The page of that day.
      assert html =~ RescordWeb.TaskWords.day(later)
      assert html =~ "Yearly check"
      assert has_element?(view, "tbody td", "09:15")
      assert has_element?(view, "tbody td", to_string(context.other.email))
      assert has_element?(view, "tbody small", "Clean")

      {:ok, [task]} = Tasks.day(later, context.options)
      {:ok, expected} = Accounts.local_instant(context.organisation, "#{later}T09:15")
      assert DateTime.compare(task.due_at, expected) == :eq
    end

    test "says what is wrong, and keeps what the member typed", context do
      {view, _html} = open(context.conn, context.path)

      html =
        view
        |> form("#task", task: %{title: "A task", date: "", time: "09:15"})
        |> render_submit()

      assert has_element?(view, "main p[role=alert]", "The time is not a date and a time")
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
      {_view, _html} = press(view, conn, "complete", task.id)

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

    assert RescordWeb.TaskWords.day(~D[2026-11-16]) == "Monday 16 November 2026"
  end
end
