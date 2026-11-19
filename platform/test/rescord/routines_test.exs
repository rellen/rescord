defmodule Rescord.RoutinesTest do
  @moduledoc """
  Holds the routines of an organisation (`docs/domain.md`, section 5.7, and
  ADR 0033): a routine makes its tasks a number of days ahead, in the time
  zone of the organisation, and never two times; a change, a pause and the
  end of a routine cancel the tasks that come and keep the work that is
  done.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  require Ash.Query

  alias Rescord.{Accounts, Journal, Tasks}
  alias Rescord.Tasks.Changes.SyncTasks
  alias Rescord.Tasks.{Routine, Task}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    # Only an administrator starts and changes a routine (ADR 0039).
    options = [actor: administrator, tenant: organisation]
    now = DateTime.utc_now()

    # A time of the day that is 6 hours from now in the organisation: no
    # test is near the instant where a task of today is in or out.
    time =
      organisation
      |> Accounts.local_time(DateTime.add(now, 6, :hour))
      |> DateTime.to_time()
      |> Time.truncate(:second)
      |> Map.put(:second, 0)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists,
     options: options,
     member_options: [actor: member, tenant: organisation],
     now: now,
     today: Accounts.today(organisation),
     time: time,
     biscuit: resident!(lists, options)}
  end

  defp start!(context, facts \\ %{}) do
    %{title: "Hay and pellets", pattern: :daily, times: [context.time], starts_on: context.today}
    |> Map.merge(facts)
    |> Tasks.start_routine!(context.options)
  end

  # Each task of a routine that is not cancelled, in the order of its time.
  defp tasks(routine, context) do
    Task
    |> Ash.Query.filter(routine_id == ^routine.id)
    |> Ash.Query.sort(due_at: :asc)
    |> Ash.read!(context.options)
  end

  defp due(tasks), do: Enum.filter(tasks, &(&1.state == :due))

  # The instants of a time of the day on each of the days from today, that
  # are after now: what a test expects with no use of the code under test.
  defp expected(context, time, days) do
    for day <- 0..days,
        instant = Accounts.local_instant(context.organisation, Date.add(context.today, day), time),
        DateTime.compare(instant, context.now) == :gt do
      instant
    end
  end

  defp local_dates(tasks, context),
    do: Enum.map(tasks, &Accounts.local_date(context.organisation, &1.due_at))

  describe "a routine" do
    test "makes a task for each of its times, 14 days ahead", context do
      second = Time.add(context.time, 60 * 60)

      routine =
        start!(context, %{
          times: [second, context.time],
          kind_id: context.lists.task_kind.feed,
          assignee_ids: [context.member.id, context.administrator.id],
          note: "Two scoops",
          resident_ids: [context.biscuit.id]
        })

      # The times are in order.
      assert routine.times == [context.time, second]

      tasks = tasks(routine, context)

      assert Enum.map(tasks, & &1.due_at) ==
               Enum.sort(
                 expected(context, context.time, 14) ++ expected(context, second, 14),
                 DateTime
               )

      assert length(tasks) in 28..30

      for task <- tasks do
        assert %{title: "Hay and pellets", note: "Two scoops", state: :due} = task
        assert task.kind_id == context.lists.task_kind.feed
        assert task.assignee_ids == [context.member.id, context.administrator.id]
      end

      {:ok, with_facts} = Tasks.task_with_facts(hd(tasks).id, context.options)
      assert Tasks.subject_names(with_facts) == ["Biscuit"]
    end

    test "has the days ahead of the organisation, or its own", context do
      {:ok, _} =
        Accounts.set_organisation_task_days_ahead(context.organisation, 3,
          actor: context.administrator
        )

      near = start!(context)
      far = start!(context, %{title: "Clean the shed", days_ahead: 40})

      assert Enum.map(tasks(near, context), & &1.due_at) == expected(context, context.time, 3)
      assert Enum.map(tasks(far, context), & &1.due_at) == expected(context, context.time, 40)
    end

    test "is on its days of the week", context do
      weekdays = [
        Date.day_of_week(context.today),
        rem(Date.day_of_week(context.today) + 2, 7) + 1
      ]

      routine = start!(context, %{pattern: :weekly, weekdays: weekdays})

      dates = local_dates(tasks(routine, context), context)
      assert length(dates) in 3..6
      assert Enum.all?(dates, &(Date.day_of_week(&1) in weekdays))
    end

    test "is every number of days, and every number of months", context do
      tomorrow = Date.add(context.today, 1)

      third = start!(context, %{pattern: :interval, every: 3, starts_on: tomorrow})

      assert local_dates(tasks(third, context), context) ==
               for(day <- [1, 4, 7, 10, 13], do: Date.add(context.today, day))

      yearly =
        start!(context, %{
          title: "Yearly check",
          pattern: :monthly,
          every: 12,
          starts_on: tomorrow,
          days_ahead: 400
        })

      assert local_dates(tasks(yearly, context), context) ==
               [tomorrow, Date.shift(tomorrow, month: 12)]
    end

    test "has no task after its last day", context do
      routine = start!(context, %{ends_on: Date.add(context.today, 2)})

      assert Enum.map(tasks(routine, context), & &1.due_at) == expected(context, context.time, 2)
    end

    test "that names a prescription makes tasks that write a dose", context do
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

      routine =
        start!(context, %{
          title: "Medicate",
          prescription_id: prescription.id,
          resident_ids: [context.biscuit.id]
        })

      [task | _] = tasks(routine, context)
      assert task.prescription_id == prescription.id

      {:ok, _done} = Tasks.complete_task(task, %{}, context.options)

      assert {:ok, [%{kind: :dose}, %{kind: :prescription}]} =
               Journal.entries(context.biscuit.id, context.options)
    end
  end

  describe "the pattern of a routine" do
    test "is in one shape", context do
      routine =
        start!(context, %{
          times: [~T[12:00:00], ~T[18:00:00], ~T[08:00:00], ~T[18:00:00]],
          weekdays: [3, 1],
          every: 5
        })

      # Each time one time, in order. A daily routine has no days of the
      # week and no number.
      assert %{times: [~T[08:00:00], ~T[12:00:00], ~T[18:00:00]], weekdays: [], every: nil} =
               routine

      weekly = start!(context, %{pattern: :weekly, weekdays: [5, 1, 5], every: 2})
      assert %{weekdays: [1, 5], every: nil} = weekly
    end

    test "needs its facts", context do
      for {facts, words} <- [
            {%{times: []}, "needs one time or more"},
            {%{times: for(hour <- 0..12, do: Time.new!(hour, 0, 0))}, "can have 12 at most"},
            {%{pattern: :weekly}, "needs one day of the week or more"},
            {%{pattern: :weekly, weekdays: [0, 8]}, "are from 1 to 7"},
            {%{pattern: :interval}, "is a number of days from 1 to 366"},
            {%{pattern: :interval, every: 367}, "is a number of days from 1 to 366"},
            {%{pattern: :monthly, every: 0}, "is a number of months from 1 to 36"},
            {%{ends_on: Date.add(context.today, -1)}, "cannot be before the first day"}
          ] do
        facts =
          Map.merge(
            %{title: "Hay", pattern: :daily, times: [context.time], starts_on: context.today},
            facts
          )

        assert {:error, %Ash.Error.Invalid{} = error} =
                 Tasks.start_routine(facts, context.options)

        assert Exception.message(error) =~ words
      end

      # A routine that is refused makes no task.
      assert Ash.read!(Task, context.options) == []
    end

    test "needs a title, a pattern and a first day", context do
      for missing <- [:title, :pattern, :starts_on] do
        facts =
          Map.delete(
            %{title: "Hay", pattern: :daily, times: [context.time], starts_on: context.today},
            missing
          )

        assert {:error, %Ash.Error.Invalid{}} = Tasks.start_routine(facts, context.options)
      end
    end
  end

  describe "the tasks of a routine, as time goes on" do
    test "are made for the later days, and never two times", context do
      routine = start!(context)
      before = length(tasks(routine, context))

      # Nothing to do now.
      assert Tasks.generate(context.organisation) == 0
      assert length(tasks(routine, context)) == before

      # Three days later, the routine gets the tasks of three more days.
      later = DateTime.add(context.now, 3, :day)
      assert Tasks.generate(context.organisation, later) == 1

      made = tasks(routine, context)
      assert length(made) == before + 3

      assert Enum.map(made, & &1.due_at) == Enum.uniq(Enum.map(made, & &1.due_at))
      assert List.last(local_dates(made, context)) == Date.add(context.today, 17)

      # The same instant again makes nothing.
      assert Tasks.generate(context.organisation, later) == 0
      assert length(tasks(routine, context)) == before + 3
    end

    test "are not made for a time before now", context do
      routine = start!(context)
      before = tasks(routine, context)

      # The job did not run for 30 days.
      later = DateTime.add(context.now, 30, :day)
      assert Tasks.generate(context.organisation, later) == 1

      new = tasks(routine, context) -- before
      assert length(new) in 14..15
      assert Enum.all?(new, &(DateTime.compare(&1.due_at, later) != :lt))
    end

    test "are made by the job, for each organisation", context do
      routine = start!(context)
      before = length(tasks(routine, context))

      {:ok, _} =
        Accounts.set_organisation_task_days_ahead(context.organisation, 20,
          actor: context.administrator
        )

      assert :ok = Rescord.Tasks.Workers.GenerateTasks.perform(%Oban.Job{})

      assert length(tasks(routine, context)) == before + 6
    end

    test "cost no write after the last day of the routine", context do
      start!(context, %{ends_on: Date.add(context.today, 1)})

      # Later days are after its last day: the job writes nothing.
      assert Tasks.generate(context.organisation, DateTime.add(context.now, 5, :day)) == 0
      assert Tasks.generate(context.organisation, DateTime.add(context.now, 60, :day)) == 0
    end

    test "are made for each organisation when one organisation has a fault", context do
      routine = start!(context)
      before = length(tasks(routine, context))

      {:ok, _} =
        Accounts.set_organisation_task_days_ahead(context.organisation, 20,
          actor: context.administrator
        )

      # An organisation whose schema is not there. The transaction of the
      # test takes the change back.
      broken = organisation!(context.root, "Aaa broken")

      Rescord.Repo.query!(
        ~s(DROP SCHEMA "#{Rescord.Accounts.Organisation.schema(broken)}" CASCADE)
      )

      assert :ok = Rescord.Tasks.Workers.GenerateTasks.perform(%Oban.Job{})
      assert length(tasks(routine, context)) == before + 6
    end

    test "are 500 in one run at most, and the next run makes the others", context do
      times = for hour <- 0..11, do: Time.new!(hour * 2, 0, 0)
      routine = start!(context, %{times: times, days_ahead: 50})

      assert length(tasks(routine, context)) == 500

      assert Tasks.generate(context.organisation) == 1
      made = tasks(routine, context)

      expected = Enum.flat_map(times, &expected(context, &1, 50))
      assert Enum.map(made, & &1.due_at) == Enum.sort(expected, DateTime)

      assert Tasks.generate(context.organisation) == 0
    end

    test "do not move the paper trail of the routine", context do
      routine = start!(context)
      Tasks.generate(context.organisation, DateTime.add(context.now, 3, :day))

      versions =
        Routine
        |> AshPaperTrail.Resource.Info.version_resource()
        |> Ash.read!(tenant: context.organisation, authorize?: false)
        |> Enum.filter(&(&1.version_source_id == routine.id))

      assert [%{version_action_name: :start, user_id: user_id}] = versions
      assert user_id == context.administrator.id
    end
  end

  describe "a routine that counts from the last task" do
    defp last_done!(context, facts \\ %{}) do
      start!(context, Map.merge(%{pattern: :interval, every: 3, count_from: :last_done}, facts))
    end

    defp day_at(context, days),
      do:
        Accounts.local_instant(context.organisation, Date.add(context.today, days), context.time)

    test "has the tasks of one day, and no more while one is due", context do
      routine = last_done!(context)

      assert [%{state: :due} = task] = tasks(routine, context)
      assert task.due_at == hd(expected(context, context.time, 14))

      # The job makes no other task while that one is due.
      Tasks.generate(context.organisation, DateTime.add(context.now, 5, :day))
      assert [_one] = tasks(routine, context)
    end

    test "makes the next day when a member completes or skips the last task", context do
      routine = last_done!(context)
      [first] = tasks(routine, context)

      # Done today: the next day is in 3 days, at the time of the routine.
      {:ok, _done} = Tasks.complete_task(first, %{}, context.member_options)
      assert [second] = due(tasks(routine, context))
      assert second.due_at == day_at(context, 3)

      # Skipped today, ahead of its day: the next day is after that day.
      {:ok, _skipped} =
        Tasks.skip_task(second, %{skip_reason: "At the clinic"}, context.member_options)

      assert [third] = due(tasks(routine, context))
      assert third.due_at == day_at(context, 4)
    end

    test "has the next day of each time of the routine when the last of a day is done",
         context do
      # A second time of the same day: no test is near midnight.
      other = Time.add(context.time, if(context.time.hour >= 12, do: -30, else: 30) * 60)
      [early, late] = Enum.sort([context.time, other], Time)
      routine = last_done!(context, %{times: [early, late], every: 2})
      [one, two] = tasks(routine, context)

      assert Accounts.local_date(context.organisation, one.due_at) ==
               Accounts.local_date(context.organisation, two.due_at)

      # One task of the day is still due: no next day yet.
      {:ok, _done} = Tasks.complete_task(one, %{}, context.member_options)
      assert Enum.map(due(tasks(routine, context)), & &1.id) == [two.id]

      {:ok, _done} = Tasks.complete_task(two, %{}, context.member_options)

      day = Date.add(context.today, 2)

      assert Enum.map(due(tasks(routine, context)), & &1.due_at) == [
               Accounts.local_instant(context.organisation, day, early),
               Accounts.local_instant(context.organisation, day, late)
             ]
    end

    test "counts from its first day with any other pattern", context do
      routine =
        start!(context, %{pattern: :weekly, weekdays: Enum.to_list(1..7), count_from: :last_done})

      assert routine.count_from == :first_day
      assert length(tasks(routine, context)) == length(expected(context, context.time, 14))
    end
  end

  describe "a change to a routine" do
    test "makes its tasks that come again, and keeps the work that is done", context do
      routine = start!(context)
      [first, second | _] = tasks(routine, context)

      {:ok, done} = Tasks.complete_task(first, %{}, context.options)
      {:ok, skipped} = Tasks.skip_task(second, %{skip_reason: "At the clinic"}, context.options)

      later = Time.add(context.time, 30 * 60)

      {:ok, revised} =
        Tasks.revise_routine(routine, %{title: "Hay only", times: [later]}, context.options)

      now = tasks(revised, context)

      # The two that a member finished stay as they were.
      assert Enum.map(now -- due(now), & &1.id) == [done.id, skipped.id]
      assert Enum.map(now -- due(now), & &1.title) == ["Hay and pellets", "Hay and pellets"]

      # Each task that is due is a new one, at the new time.
      assert Enum.map(due(now), & &1.due_at) == expected(context, later, 14)
      assert Enum.all?(due(now), &(&1.title == "Hay only"))
    end

    test "makes no second task for a time that a member finished ahead", context do
      routine = start!(context)
      before = tasks(routine, context)
      {:ok, done} = Tasks.complete_task(hd(before), %{}, context.options)

      {:ok, revised} = Tasks.revise_routine(routine, %{title: "Hay only"}, context.options)

      now = tasks(revised, context)
      assert Enum.map(now, & &1.due_at) == Enum.map(before, & &1.due_at)
      assert [%{id: id, state: :done, title: "Hay and pellets"} | coming] = now
      assert id == done.id
      assert Enum.all?(coming, &(&1.title == "Hay only" and &1.state == :due))
    end

    test "keeps a task that is late", context do
      routine = start!(context)
      [first | _] = tasks(routine, context)

      # The task is late: its time is before now.
      Ash.Seed.update!(first, %{due_at: DateTime.add(context.now, -1, :hour)})

      {:ok, revised} = Tasks.revise_routine(routine, %{title: "Hay only"}, context.options)

      assert %{title: "Hay and pellets", state: :due} = hd(tasks(revised, context))
    end

    test "is refused with a pattern that is not whole, and changes no task", context do
      routine = start!(context)
      before = tasks(routine, context)

      assert {:error, %Ash.Error.Invalid{}} =
               Tasks.revise_routine(routine, %{pattern: :weekly}, context.options)

      assert tasks(routine, context) == before
    end
  end

  describe "a pause" do
    test "cancels the tasks that come, and the routine makes them again after it", context do
      routine = start!(context)
      before = Enum.map(tasks(routine, context), & &1.due_at)

      {:ok, paused} = Tasks.pause_routine(routine, context.options)
      assert paused.paused
      assert tasks(paused, context) == []

      # The job makes nothing for a routine that is paused.
      assert Tasks.generate(context.organisation, DateTime.add(context.now, 3, :day)) == 0
      assert tasks(paused, context) == []

      {:ok, resumed} = Tasks.resume_routine(paused, context.options)
      refute resumed.paused
      assert Enum.map(tasks(resumed, context), & &1.due_at) == before
    end
  end

  describe "a change to a routine that is paused" do
    test "makes no task, and the routine has the new facts when it starts again", context do
      routine = start!(context)
      {:ok, paused} = Tasks.pause_routine(routine, context.options)

      {:ok, revised} = Tasks.revise_routine(paused, %{title: "Hay only"}, context.options)
      assert revised.paused
      assert tasks(revised, context) == []

      {:ok, resumed} = Tasks.resume_routine(revised, context.options)
      assert [%{title: "Hay only"} | _] = tasks(resumed, context)
    end
  end

  describe "the end of a routine" do
    test "cancels the tasks that come, and keeps the work that is done", context do
      routine = start!(context)
      [first | _] = tasks(routine, context)
      {:ok, done} = Tasks.complete_task(first, %{}, context.options)

      assert :ok = Tasks.remove_routine(routine, context.options)

      assert {:ok, []} = Tasks.routines(context.options)
      assert {:ok, nil} = Tasks.routine(routine.id, context.options)
      assert Enum.map(tasks(routine, context), & &1.id) == [done.id]

      # The job makes nothing for a routine that ended.
      assert Tasks.generate(context.organisation, DateTime.add(context.now, 3, :day)) == 0
    end
  end

  describe "the routines with their facts" do
    test "are in the order of their titles, each with its kind and its next task", context do
      start!(context, %{title: "Water"})
      hay = start!(context, %{title: "Hay", kind_id: context.lists.task_kind.feed})
      {:ok, _} = Tasks.pause_routine(hay, context.options)

      assert {:ok, [hay, water]} = Tasks.routines_with_facts(context.now, context.options)

      assert to_string(hay.kind.label) == "Feed"
      assert Tasks.next_task_at(hay) == nil
      assert Tasks.next_task_at(water) == hd(expected(context, context.time, 14))
    end
  end

  describe "who can work with the routines" do
    test "an administrator and a root user change them, and a member reads them", context do
      routine = start!(context)
      assert {:ok, [_routine]} = Tasks.routines(actor: context.root, tenant: context.organisation)
      assert {:ok, [_routine]} = Tasks.routines(context.member_options)

      facts = %{title: "Hay", pattern: :daily, times: [context.time], starts_on: context.today}
      assert {:error, %Ash.Error.Forbidden{}} = Tasks.start_routine(facts, context.member_options)

      for action <- [:pause_routine, :remove_routine] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 apply(Tasks, action, [routine, context.member_options])
      end

      assert {:error, %Ash.Error.Forbidden{}} =
               Tasks.revise_routine(routine, %{title: "X"}, context.member_options)

      paused = Tasks.pause_routine!(routine, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Tasks.resume_routine(paused, context.member_options)

      refute Tasks.role_can_routine?(:member, :start)
      assert Tasks.role_can_routine?(:member, :read)
      assert Tasks.role_can_routine?(:administrator, :start)
    end

    test "not a user of another organisation or nobody", context do
      routine = start!(context)

      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      facts = %{title: "Hay", pattern: :daily, times: [context.time], starts_on: context.today}

      for actor <- [outsider, nil] do
        options = [actor: actor, tenant: context.organisation]

        assert {:ok, []} = Tasks.routines(options)
        assert {:error, %Ash.Error.Forbidden{}} = Tasks.start_routine(facts, options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Tasks.revise_routine(routine, %{title: "X"}, options)

        assert {:error, %Ash.Error.Forbidden{}} = Tasks.pause_routine(routine, options)
        assert {:error, %Ash.Error.Forbidden{}} = Tasks.remove_routine(routine, options)
      end

      refute Tasks.role_can_routine?(nil, :start)
    end

    test "no member runs what Rescord runs itself", context do
      routine = start!(context)

      for {action, input} <- [generate: %{}, mark: %{until: DateTime.utc_now()}] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 routine
                 |> Ash.Changeset.for_update(action, input, context.options)
                 |> Ash.update()
      end

      assert {:error, %Ash.Error.Forbidden{}} =
               Task
               |> Ash.Changeset.for_create(
                 :generate,
                 %{title: "X", due_at: DateTime.utc_now(), routine_id: routine.id},
                 context.options
               )
               |> Ash.create()

      refute Tasks.role_can_routine?(:administrator, :generate)
      refute Tasks.role_can?(:administrator, :generate)
    end

    test "no action takes the pause or the mark as input", context do
      routine = start!(context)

      for input <- [%{paused: true}, %{generated_until: DateTime.utc_now()}] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Tasks.revise_routine(routine, input, context.options)
      end
    end
  end

  describe "the instants of a routine" do
    test "are in the time zone of the organisation", context do
      # Brisbane is 10 hours ahead of UTC.
      routine = %{
        pattern: :daily,
        every: nil,
        weekdays: [],
        starts_on: ~D[2026-11-16],
        ends_on: nil,
        times: [~T[08:00:00], ~T[18:30:00]]
      }

      assert SyncTasks.instants(
               routine,
               context.organisation,
               ~U[2026-11-15 22:00:00Z],
               ~U[2026-11-17 14:00:00Z]
             ) == [
               ~U[2026-11-15 22:00:00Z],
               ~U[2026-11-16 08:30:00Z],
               ~U[2026-11-16 22:00:00Z],
               ~U[2026-11-17 08:30:00Z]
             ]

      # The first instant is in, and the last one is not.
      assert SyncTasks.instants(
               routine,
               context.organisation,
               ~U[2026-11-15 22:00:01Z],
               ~U[2026-11-16 08:30:00Z]
             ) == []
    end

    test "are one for a time that the clocks skip, and for a time that comes two times",
         context do
      harbour = organisation!(context.root, "Harbour", "Australia/Sydney")

      routine = %{
        pattern: :daily,
        every: nil,
        weekdays: [],
        starts_on: ~D[2026-10-04],
        ends_on: nil,
        times: [~T[02:30:00], ~T[03:00:00]]
      }

      # On 4 October 2026 the clocks of Sydney go from 02:00 to 03:00. The
      # time 02:30 is not there: its task is at 03:00, with the other one.
      assert SyncTasks.instants(
               routine,
               harbour,
               ~U[2026-10-03 13:00:00Z],
               ~U[2026-10-04 13:00:00Z]
             ) ==
               [~U[2026-10-03 16:00:00Z]]

      # On 4 April 2027 the clocks go from 03:00 to 02:00, so 02:30 comes
      # two times. The task is at the first one.
      assert Accounts.local_instant(harbour, ~D[2027-04-04], ~T[02:30:00]) ==
               ~U[2027-04-03 15:30:00Z]
    end

    test "stop at the end of the day that is the number of days ahead", context do
      routine = %{days_ahead: nil}

      # 02:00 UTC on 16 November is 12:00 in Brisbane. 14 days ahead is
      # 30 November, and that day ends at 14:00 UTC.
      assert SyncTasks.horizon(routine, context.organisation, ~U[2026-11-16 02:00:00Z]) ==
               ~U[2026-11-30 14:00:00Z]

      assert SyncTasks.horizon(%{days_ahead: 1}, context.organisation, ~U[2026-11-16 02:00:00Z]) ==
               ~U[2026-11-17 14:00:00Z]
    end
  end
end
