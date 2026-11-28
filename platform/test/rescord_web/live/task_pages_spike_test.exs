defmodule RescordWeb.TaskPagesSpikeTest do
  @moduledoc "Spike: the tasks page with PhoenixTest and the locators of RescordWeb.Roles."

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Tasks}

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]

    {:ok,
     organisation: organisation,
     member: member,
     options: options,
     today: Accounts.today(organisation),
     biscuit: resident!(lists, options),
     path: ~p"/o/#{organisation.short_name}/tasks",
     conn: sign_in(context.conn, member)}
  end

  defp today_at(context, time) do
    {:ok, instant} =
      Accounts.local_instant(context.organisation, "#{Date.to_iso8601(context.today)}T#{time}")

    instant
  end

  defp plan!(context, attributes) do
    Tasks.plan_task!(Map.merge(%{title: "Hay and pellets"}, attributes), context.options)
  end

  test "the tasks of today, then of the day after", context do
    plan!(context, %{due_at: today_at(context, "23:30"), resident_ids: [context.biscuit.id]})

    plan!(context, %{
      title: "Tomorrow",
      due_at: DateTime.add(today_at(context, "23:30"), 1, :hour)
    })

    tasks = region("Tasks of the day")

    context.conn
    |> visit(context.path)
    |> assert_has(main() |> heading(level: 1), text: "Tasks")
    |> assert_has(tasks |> row(~r/^Hay and pellets/), text: "11:30 pm Biscuit Anybody")
    |> refute_has(tasks, text: "Tomorrow")
    |> click(link("The day after"))
    |> assert_has(tasks |> row(~r/^Tomorrow/), text: "12:30 am")
    |> refute_has(tasks, text: "Hay and pellets")
  end

  test "a task is taken, done, and opened again", context do
    task = plan!(context, %{due_at: DateTime.add(DateTime.utc_now(), 30, :minute)})
    date = Accounts.local_date(context.organisation, task.due_at)
    tasks = region("Tasks of the day")

    context.conn
    |> visit(context.path <> "?day=#{date}")
    |> click(tasks |> button("Take the task #{task.title}"))
    |> assert_has(tasks, text: to_string(context.member.email))
    |> refute_has(tasks |> button("Take the task #{task.title}"))
    |> click(tasks |> button("Mark the task #{task.title} as done"))
    |> assert_has(tasks |> row(~r/^Hay and pellets/), text: "Done")
    |> click(tasks |> button("Open again the task #{task.title}"))
    |> assert_has(tasks |> row(~r/^Hay and pellets/), text: "Due")
  end

  test "a new task, by the labels of its form", context do
    context.conn
    |> visit(context.path)
    |> within(main(), fn session ->
      session
      |> fill_in("What to do", with: "Clean the hutch")
      |> fill_in("Time", with: "23:45")
      |> click_button("Plan the task")
    end)
    |> assert_has(region("Tasks of the day") |> row(~r/^Clean the hutch/))
  end

  test "the search and a filter of Cinder, by their labels", context do
    plan!(context, %{title: "Clean the hutch", due_at: today_at(context, "09:00")})
    plan!(context, %{title: "Hay and pellets", due_at: today_at(context, "10:00")})
    tasks = region("Tasks of the day")

    session =
      context.conn
      |> visit(context.path)
      |> within(tasks, &fill_in(&1, "Search", with: "hay"))
      |> assert_has(tasks |> row(~r/^Hay and pellets/))
      |> refute_has(tasks, text: "Clean the hutch")

    session
  end
end
