defmodule Rescord.SignalsTest do
  @moduledoc """
  Holds what the other domains do when a resident is removed (ADR 0067):
  the residents emit `:resident_removed`, and the locations and the tasks
  listen. The residents do not know them.

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

  defp plan!(context, resident_ids) do
    Tasks.plan_task!(
      %{
        title: "Weigh",
        due_at: DateTime.add(DateTime.utc_now(), 1, :hour),
        resident_ids: resident_ids
      },
      context.admin
    )
  end

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

    test "takes the resident out of each task, and the task stays", context do
      both = plan!(context, [context.fern.id, context.sage.id])
      alone = plan!(context, [context.fern.id])

      assert :ok = Residents.remove_resident(context.fern, context.admin)

      assert subjects(context, both) == [context.sage.id]
      assert subjects(context, alone) == []

      # The two tasks are due as before, and a page reads them.
      {:ok, tasks} = Tasks.tasks(context.admin)
      assert Enum.sort(Enum.map(tasks, & &1.id)) == Enum.sort([both.id, alone.id])
      assert Enum.all?(tasks, &(&1.state == :due))
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
    end
  end

  describe "an action that only a listener runs" do
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
               routine
               |> Ash.Changeset.for_update(
                 :forget_resident,
                 %{resident_id: context.fern.id},
                 context.admin
               )
               |> Ash.update()

      assert subjects(context, task) == [context.fern.id]
    end
  end
end
