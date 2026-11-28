defmodule Rescord.SignalsTest do
  @moduledoc """
  Holds what the other domains do when a resident is removed, and when a
  resident leaves (ADR 0067): the residents emit `:resident_removed` and
  `:resident_departed`, and the locations and the tasks listen. The
  residents do not know them.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Ash.Signals.Test
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  require Ash.Query

  alias Rescord.{Accounts, Locations, Residents, Tasks}
  alias Rescord.Locations.Placement
  alias Rescord.Residents.Signals
  alias Rescord.Tasks.{Routine, TaskSubject}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]

    shed = Locations.add_location!(%{name: "Main shed"}, admin)
    fern = resident!(lists, admin, %{name: "Fern", sex: :female})
    sage = resident!(lists, admin, %{name: "Sage", sex: :female})

    for resident <- [fern, sage] do
      {:ok, _placement} = Locations.settle({:resident, resident.id}, shed.id, admin)
    end

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     admin: admin,
     lists: lists,
     shed: shed,
     fern: fern,
     sage: sage}
  end

  # What the database holds, with no policy.
  defp placed(context, extra \\ []) do
    Placement
    |> Ash.read!([tenant: context.organisation, authorize?: false] ++ extra)
    |> Enum.map(& &1.resident_id)
    |> Enum.sort()
  end

  defp subjects(context, task) do
    TaskSubject
    |> Ash.Query.filter(task_id == ^task.id)
    |> Ash.read!(tenant: context.organisation, authorize?: false)
    |> Enum.map(& &1.resident_id)
    |> Enum.sort()
  end

  defp plan!(context, resident_ids, more \\ %{}) do
    Tasks.plan_task!(
      Map.merge(
        %{
          title: "Weigh",
          due_at: DateTime.add(DateTime.utc_now(), 1, :hour),
          resident_ids: resident_ids
        },
        more
      ),
      context.admin
    )
  end

  defp depart!(context, resident, options \\ nil) do
    Residents.record_departure!(
      %{resident_id: resident.id, kind: :release, departed_on: Date.utc_today()},
      options || context.admin
    )
  end

  # A task as the database holds it, with no policy.
  defp task!(context, task),
    do: Ash.get!(Tasks.Task, task.id, tenant: context.organisation, authorize?: false)

  defp start!(context, resident_ids) do
    time = Time.truncate(Time.add(Time.utc_now(), 6, :hour), :second)

    Tasks.start_routine!(
      %{
        title: "Hay and pellets",
        pattern: :daily,
        times: [%{time | second: 0}],
        starts_on: Accounts.today(context.organisation),
        resident_ids: resident_ids
      },
      context.admin
    )
  end

  describe "the removal of a resident" do
    test "emits the signal, with the resident", context do
      fern_id = context.fern.id

      assert_emits_signal(Signals, :resident_removed, %{resident_id: ^fern_id}, fn ->
        :ok = Residents.remove_resident(context.fern, context.admin)
      end)
    end

    test "ends the placement of the resident, and no other", context do
      before = DateTime.utc_now()
      assert placed(context) == Enum.sort([context.fern.id, context.sage.id])

      assert :ok = Residents.remove_resident(context.fern, context.admin)

      assert placed(context) == [context.sage.id]
      # The placement is history: a read as of the time before finds it.
      assert context.fern.id in placed(context, as_of: before)
    end

    test "ends the placement as of the instant of the removal", context do
      later = DateTime.add(DateTime.utc_now(), 2, :day)

      assert :ok = Residents.remove_resident(context.fern, context.admin ++ [as_of: later])

      assert context.fern.id in placed(context, as_of: DateTime.add(later, -1, :day))
      refute context.fern.id in placed(context, as_of: DateTime.add(later, 1, :day))
    end

    test "takes the resident out of each task, and a task with another subject stays due",
         context do
      both = plan!(context, [context.fern.id, context.sage.id])
      housed = plan!(context, [context.fern.id], %{location_ids: [context.shed.id]})

      assert :ok = Residents.remove_resident(context.fern, context.admin)

      assert subjects(context, both) == [context.sage.id]
      # The subject that stays is the location, which names no resident.
      assert subjects(context, housed) == [nil]

      for task <- [both, housed] do
        assert %{state: :due, skip_reason: nil, finished_at: nil} = task!(context, task)
      end
    end

    test "skips a task that named only the resident, with the reason", context do
      alone = plan!(context, [context.fern.id])
      administrator_id = context.administrator.id

      assert :ok = Residents.remove_resident(context.fern, context.admin)

      assert subjects(context, alone) == []

      assert %{
               state: :skipped,
               skip_reason: "The resident was removed",
               finished_by_id: ^administrator_id,
               finished_at: %DateTime{}
             } = task!(context, alone)

      # A page reads the task, and a member opens it again.
      {:ok, [task]} = Tasks.tasks(context.admin)
      assert {:ok, opened} = Tasks.reopen_task(task, context.admin)
      assert %{state: :due, skip_reason: nil, finished_at: nil} = opened
    end

    test "skips the task when its last resident goes, and not before", context do
      task = plan!(context, [context.fern.id, context.sage.id])

      assert :ok = Residents.remove_resident(context.fern, context.admin)
      assert %{state: :due} = task!(context, task)

      assert :ok = Residents.remove_resident(context.sage, context.admin)
      assert %{state: :skipped, skip_reason: "The resident was removed"} = task!(context, task)
    end

    test "leaves a task that is done as it is", context do
      task = plan!(context, [context.fern.id])
      {:ok, done} = Tasks.complete_task(task, %{}, context.admin)

      assert :ok = Residents.remove_resident(context.fern, context.admin)

      assert subjects(context, task) == []
      kept = task!(context, task)
      assert %{state: :done, skip_reason: nil} = kept
      assert kept.finished_at == done.finished_at
    end

    test "takes the resident out of each routine, and out of the tasks that it made",
         context do
      routine = start!(context, [context.fern.id, context.sage.id])
      other = start!(context, [context.sage.id])

      assert :ok = Residents.remove_resident(context.fern, context.admin)

      assert {:ok, %Routine{resident_ids: ids}} = Tasks.routine(routine.id, context.admin)
      assert ids == [context.sage.id]
      assert {:ok, %Routine{resident_ids: kept}} = Tasks.routine(other.id, context.admin)
      assert kept == [context.sage.id]

      made =
        TaskSubject
        |> Ash.Query.filter(resident_id == ^context.fern.id)
        |> Ash.read!(tenant: context.organisation, authorize?: false)

      assert made == []
    end

    test "skips the tasks of a routine that named only the resident", context do
      routine = start!(context, [context.fern.id])

      assert :ok = Residents.remove_resident(context.fern, context.admin)

      tasks =
        Tasks.Task
        |> Ash.Query.filter(routine_id == ^routine.id)
        |> Ash.read!(tenant: context.organisation, authorize?: false)

      assert tasks != []

      for task <- tasks do
        assert %{state: :skipped, skip_reason: "The resident was removed"} = task
      end
    end

    test "needs no grant for the placements, the tasks or the routines", context do
      # A role that removes residents, and does nothing else.
      {:ok, role} =
        Accounts.define_role(%{name: "Registrar", powers: [:remove_residents]}, context.admin)

      {member, registrar} = member!(context.organisation, :member, context.administrator)
      {:ok, _member} = Accounts.set_member_role(member, role.id, context.admin)
      options = [actor: registrar, tenant: context.organisation]

      task = plan!(context, [context.fern.id])
      routine = start!(context, [context.fern.id])

      # The role cannot end a placement by itself.
      [placement | _] =
        Ash.read!(Placement, tenant: context.organisation, authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} = Locations.finish_placement(placement, options)

      assert :ok = Residents.remove_resident(context.fern, options)
      assert placed(context) == [context.sage.id]
      assert subjects(context, task) == []
      assert {:ok, %Routine{resident_ids: []}} = Tasks.routine(routine.id, context.admin)

      # The task named only the resident. The role cannot skip a task, and
      # the removal skips this one in the name of the person.
      registrar_id = registrar.id
      assert %{state: :skipped, finished_by_id: ^registrar_id} = task!(context, task)
    end
  end

  describe "the departure of a resident" do
    test "emits the signal, with the resident", context do
      fern_id = context.fern.id

      assert_emits_signal(Signals, :resident_departed, %{resident_id: ^fern_id}, fn ->
        depart!(context, context.fern)
      end)
    end

    test "ends the placement of the resident, and no other", context do
      before = DateTime.utc_now()

      depart!(context, context.fern)

      assert placed(context) == [context.sage.id]
      assert context.fern.id in placed(context, as_of: before)
    end

    test "takes the resident out of each routine", context do
      routine = start!(context, [context.fern.id, context.sage.id])

      depart!(context, context.fern)

      assert {:ok, %Routine{resident_ids: ids}} = Tasks.routine(routine.id, context.admin)
      assert ids == [context.sage.id]
    end

    test "takes the resident out of each task that is due, and skips a task left alone",
         context do
      both = plan!(context, [context.fern.id, context.sage.id])
      alone = plan!(context, [context.fern.id])
      administrator_id = context.administrator.id

      depart!(context, context.fern)

      assert subjects(context, both) == [context.sage.id]
      assert %{state: :due, skip_reason: nil} = task!(context, both)

      assert subjects(context, alone) == []

      assert %{
               state: :skipped,
               skip_reason: "The resident left",
               finished_by_id: ^administrator_id,
               finished_at: %DateTime{}
             } = task!(context, alone)

      # A member opens the task again.
      assert {:ok, %{state: :due, skip_reason: nil}} =
               Tasks.reopen_task(task!(context, alone), context.admin)
    end

    test "leaves the resident in a task that is done: it is its history", context do
      task = plan!(context, [context.fern.id])
      {:ok, _done} = Tasks.complete_task(task, %{}, context.admin)

      depart!(context, context.fern)

      assert subjects(context, task) == [context.fern.id]
      assert %{state: :done, skip_reason: nil} = task!(context, task)
    end

    test "needs no grant for the placements, the tasks or the routines", context do
      # A role that has the care of the residents, and does nothing else.
      {:ok, role} = Accounts.define_role(%{name: "Carer", powers: [:residents]}, context.admin)

      {member, carer} = member!(context.organisation, :member, context.administrator)
      {:ok, _member} = Accounts.set_member_role(member, role.id, context.admin)
      options = [actor: carer, tenant: context.organisation]
      carer_id = carer.id

      task = plan!(context, [context.fern.id])
      routine = start!(context, [context.fern.id])

      depart!(context, context.fern, options)

      assert placed(context) == [context.sage.id]
      assert subjects(context, task) == []
      assert %{state: :skipped, finished_by_id: ^carer_id} = task!(context, task)
      assert {:ok, %Routine{resident_ids: []}} = Tasks.routine(routine.id, context.admin)
    end

    test "restores nothing when a member withdraws the departure", context do
      task = plan!(context, [context.fern.id])
      routine = start!(context, [context.fern.id])

      departure = depart!(context, context.fern)
      assert :ok = Residents.withdraw_departure(departure, context.admin)

      assert placed(context) == [context.sage.id]
      assert subjects(context, task) == []
      assert %{state: :skipped, skip_reason: "The resident left"} = task!(context, task)
      assert {:ok, %Routine{resident_ids: []}} = Tasks.routine(routine.id, context.admin)
    end
  end

  describe "an action that only a listener runs" do
    test "does not skip a task that a member finished a moment before", context do
      stale = plan!(context, [context.fern.id])
      {:ok, _done} = Tasks.complete_task(stale, %{}, context.admin)

      # `Rescord.Tasks.Changes.SkipTaskLeftAlone` reads this error as "the
      # task stays". The record in hand says `due`, and the database `done`.
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} =
               stale
               |> Ash.Changeset.for_update(:skip_left_alone, %{reason: "None"},
                 tenant: context.organisation,
                 authorize?: false
               )
               |> Ash.update()

      assert %{state: :done} = task!(context, stale)
    end

    test "is refused for a person, an administrator too", context do
      task = plan!(context, [context.fern.id])
      routine = start!(context, [context.fern.id])

      [subject] =
        TaskSubject
        |> Ash.Query.filter(task_id == ^task.id)
        |> Ash.read!(tenant: context.organisation, authorize?: false)

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.destroy(subject, [action: :drop] ++ context.admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.destroy(subject, [action: :drop_departed] ++ context.admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               routine
               |> Ash.Changeset.for_update(
                 :forget_resident,
                 %{resident_id: context.fern.id},
                 context.admin
               )
               |> Ash.update()

      assert {:error, %Ash.Error.Forbidden{}} =
               task
               |> Ash.Changeset.for_update(:skip_left_alone, %{reason: "None"}, context.admin)
               |> Ash.update()

      assert subjects(context, task) == [context.fern.id]
      assert %{state: :due} = task!(context, task)
    end
  end
end
