defmodule Rescord.TasksTest do
  @moduledoc """
  Holds the tasks of an organisation (`docs/domain.md`, section 5.7, and
  ADR 0032): what a task is for, its states, who can take it, the tasks of a
  day in the time zone of the organisation, and the dose that a completed
  task writes to the journal.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Journal, Locations, Residents, Tasks}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    {_, other} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     other: other,
     lists: lists,
     options: options,
     biscuit: resident!(lists, options),
     soon: DateTime.add(DateTime.utc_now(), 1, :hour) |> DateTime.truncate(:second)}
  end

  defp plan!(context, attributes \\ %{}) do
    Tasks.plan_task!(
      Map.merge(%{title: "Hay and pellets", due_at: context.soon}, attributes),
      context.options
    )
  end

  describe "a task" do
    test "is due at a time, with a kind, for a member or for each member", context do
      task = plan!(context, %{kind_id: context.lists.task_kind.feed})

      assert task.state == :due
      assert task.assignee_id == nil

      {:ok, loaded} = Tasks.task_with_facts(task.id, context.options)
      assert to_string(loaded.kind.label) == "Feed"
      assert Tasks.subject_names(loaded) == []
    end

    test "can be months ahead", context do
      later = DateTime.add(context.soon, 200, :day)
      assert %{due_at: ^later} = plan!(context, %{title: "Yearly check", due_at: later})
    end

    test "is for a resident, a group and a location", context do
      options = context.options
      sage = resident!(context.lists, options, %{name: "Sage"})
      group = Residents.form_group!(%{resident_ids: [context.biscuit.id, sage.id]}, options)

      location =
        Locations.add_location!(%{name: "East 1"},
          actor: context.administrator,
          tenant: context.organisation
        )

      task =
        plan!(context, %{
          resident_ids: [context.biscuit.id],
          group_ids: [group.id],
          location_ids: [location.id]
        })

      {:ok, loaded} = Tasks.task_with_facts(task.id, options)
      assert Enum.sort(Tasks.subject_names(loaded)) == ["Biscuit", "Biscuit and Sage", "East 1"]
    end

    test "has a subject that is one thing only", context do
      task = plan!(context)

      for subject <- [%{resident_id: context.biscuit.id, group_id: Ash.UUID.generate()}, %{}] do
        assert_raise Ash.Error.Invalid, fn ->
          Ash.Seed.seed!(Tasks.TaskSubject, Map.put(subject, :task_id, task.id),
            tenant: context.organisation
          )
        end
      end
    end

    test "needs a title and a time", context do
      assert {:error, %Ash.Error.Invalid{}} = Tasks.plan_task(%{title: "x"}, context.options)

      assert {:error, %Ash.Error.Invalid{}} =
               Tasks.plan_task(%{due_at: context.soon}, context.options)
    end
  end

  describe "the states of a task" do
    test "go from due to done, and the task says who finished it and when", context do
      task = plan!(context)
      other = [actor: context.other, tenant: context.organisation]

      assert {:ok, done} = Tasks.complete_task(task, %{}, other)
      assert done.state == :done
      assert done.finished_by_id == context.other.id
      assert %DateTime{} = done.finished_at

      # A task that is done is not completed or skipped again.
      assert {:error, %Ash.Error.Invalid{}} = Tasks.complete_task(done, %{}, other)
      assert {:error, %Ash.Error.Invalid{}} = Tasks.skip_task(done, %{skip_reason: "x"}, other)
    end

    test "go from due to skipped, with a reason", context do
      task = plan!(context)

      assert {:error, %Ash.Error.Invalid{} = error} = Tasks.skip_task(task, %{}, context.options)
      assert Exception.message(error) =~ "is required to skip a task"

      assert {:ok, skipped} =
               Tasks.skip_task(task, %{skip_reason: "The clinic has her today"}, context.options)

      assert skipped.state == :skipped
      assert skipped.finished_by_id == context.member.id
    end

    test "are not opened again two times from the same page", context do
      task = plan!(context)
      {:ok, done} = Tasks.complete_task(task, %{}, context.options)

      assert {:ok, _due} = Tasks.reopen_task(done, context.options)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} =
               Tasks.reopen_task(done, context.options)
    end

    test "go to due again when a member opens the task again", context do
      task = plan!(context)
      {:ok, skipped} = Tasks.skip_task(task, %{skip_reason: "No hay"}, context.options)

      assert {:ok, again} = Tasks.reopen_task(skipped, context.options)

      assert {again.state, again.finished_at, again.finished_by_id, again.skip_reason} ==
               {:due, nil, nil, nil}

      # A task that is due is not opened again.
      assert {:error, %Ash.Error.Invalid{}} = Tasks.reopen_task(again, context.options)
    end

    test "are in the paper trail, with who made each change", context do
      task = plan!(context)
      other = [actor: context.other, tenant: context.organisation]
      {:ok, _} = Tasks.complete_task(task, %{}, other)

      version = AshPaperTrail.Resource.Info.version_resource(Tasks.Task)

      versions =
        version
        |> Ash.read!(tenant: context.organisation, authorize?: false)
        |> Enum.filter(&(&1.version_source_id == task.id))
        |> Map.new(&{&1.version_action_name, &1.user_id})

      assert versions == %{plan: context.member.id, complete: context.other.id}
    end
  end

  describe "who a task is for" do
    test "is the member who takes it, or the member that somebody gives it to", context do
      task = plan!(context)
      other = [actor: context.other, tenant: context.organisation]

      assert {:ok, %{assignee_id: taken}} = Tasks.take_task(task, other)
      assert taken == context.other.id

      assert {:ok, %{assignee_id: given}} =
               Tasks.give_task(task, %{assignee_id: context.member.id}, other)

      assert given == context.member.id

      # For each member again.
      assert {:ok, %{assignee_id: nil}} = Tasks.give_task(task, %{assignee_id: nil}, other)
    end

    test "does not stop another member from the work", context do
      task = plan!(context, %{assignee_id: context.member.id})
      other = [actor: context.other, tenant: context.organisation]

      assert {:ok, %{state: :done}} = Tasks.complete_task(task, %{}, other)
    end
  end

  describe "the tasks of a day" do
    test "are the ones that are due on that day in the time zone of the organisation", context do
      # Brisbane is 10 hours ahead of UTC: its 16 November is from 14:00 on
      # 15 November to 14:00 on 16 November in UTC.
      at = fn time ->
        plan!(context, %{
          title: time,
          due_at: DateTime.from_naive!(NaiveDateTime.from_iso8601!(time), "Etc/UTC")
        })
      end

      at.("2026-11-15T13:59:00")
      at.("2026-11-15T14:00:00")
      at.("2026-11-16T13:59:00")
      at.("2026-11-16T14:00:00")

      {:ok, tasks} = Tasks.day(~D[2026-11-16], context.options)
      assert Enum.map(tasks, & &1.title) == ["2026-11-15T14:00:00", "2026-11-16T13:59:00"]

      assert Rescord.Accounts.day_range(context.organisation, ~D[2026-11-16]) ==
               {~U[2026-11-15 14:00:00Z], ~U[2026-11-16 14:00:00Z]}
    end

    test "say which task is overdue", context do
      now = DateTime.utc_now()
      late = plan!(context, %{title: "Late", due_at: DateTime.add(now, -1, :hour)})
      soon = plan!(context, %{title: "Soon"})
      done = plan!(context, %{title: "Done", due_at: DateTime.add(now, -2, :hour)})
      {:ok, done} = Tasks.complete_task(done, %{}, context.options)

      assert Tasks.phase(late, now) == :overdue
      assert Tasks.phase(soon, now) == :due
      assert Tasks.phase(done, now) == :done

      assert {:ok, [%{title: "Late"}]} = Tasks.overdue(now, context.options)
    end
  end

  describe "a task that names a prescription" do
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
      {:ok, prescription: prescription}
    end

    test "writes a journal entry for the dose when a member completes it", context do
      task =
        plan!(context, %{
          title: "Medicate, morning dose",
          prescription_id: context.prescription.id,
          resident_ids: [context.biscuit.id]
        })

      other = [actor: context.other, tenant: context.organisation]
      assert {:ok, done} = Tasks.complete_task(task, %{}, other)

      {:ok, [dose, _prescription]} = Journal.entries(context.biscuit.id, context.options)

      assert dose.kind == :dose
      assert dose.dose.prescription.medication == "A sample antibiotic"
      assert dose.author_id == context.other.id
      assert dose.note == "From the task: Medicate, morning dose"
      assert DateTime.compare(dose.happened_at, done.finished_at) == :eq
    end

    test "writes no entry when a member skips it, or for a task with no prescription", context do
      medicate = plan!(context, %{title: "Medicate", prescription_id: context.prescription.id})
      {:ok, _} = Tasks.skip_task(medicate, %{skip_reason: "At the clinic"}, context.options)

      {:ok, _} = Tasks.complete_task(plan!(context), %{}, context.options)

      assert {:ok, [%{kind: :prescription}]} =
               Journal.entries(context.biscuit.id, context.options)
    end

    test "writes one dose when two members complete it from the same page", context do
      task = plan!(context, %{title: "Medicate", prescription_id: context.prescription.id})
      other = [actor: context.other, tenant: context.organisation]

      # Each member has the task as it was: due.
      assert {:ok, _done} = Tasks.complete_task(task, %{}, context.options)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} =
               Tasks.complete_task(task, %{}, other)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} =
               Tasks.skip_task(task, %{skip_reason: "Late"}, other)

      {:ok, entries} = Journal.entries(context.biscuit.id, context.options)
      assert Enum.map(entries, & &1.kind) == [:dose, :prescription]

      {:ok, done} = Tasks.task(task.id, context.options)
      assert done.finished_by_id == context.member.id
    end

    test "is not done when the entry for the dose cannot be written", context do
      task = plan!(context, %{title: "Medicate", prescription_id: Ash.UUID.generate()})

      assert {:error, _error} = Tasks.complete_task(task, %{}, context.options)
      assert {:ok, %{state: :due}} = Tasks.task(task.id, context.options)
    end
  end

  describe "who can work with the tasks" do
    test "each member and a root user, and not a user of another organisation or nobody",
         context do
      task = plan!(context)
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      for actor <- [outsider, nil] do
        options = [actor: actor, tenant: context.organisation]

        assert {:ok, []} = Tasks.day(Rescord.Accounts.today(context.organisation), options)
        assert {:ok, nil} = Tasks.task(task.id, options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Tasks.plan_task(%{title: "x", due_at: context.soon}, options)

        assert {:error, %Ash.Error.Forbidden{}} = Tasks.complete_task(task, %{}, options)
        assert {:error, %Ash.Error.Forbidden{}} = Tasks.take_task(task, options)
      end

      root = [actor: context.root, tenant: context.organisation]
      assert {:ok, %{state: :done}} = Tasks.complete_task(task, %{}, root)

      assert Tasks.role_can?(:member, :complete)
      refute Tasks.role_can?(nil, :read)
    end

    test "no action takes the state, or who finished a task, as input", context do
      for action <- [:plan, :revise, :complete, :skip, :give] do
        accept = Ash.Resource.Info.action(Tasks.Task, action).accept
        refute :state in accept
        refute :finished_by_id in accept
        refute :finished_at in accept
      end

      assert {:error, %Ash.Error.Invalid{}} =
               Tasks.plan_task(%{title: "x", due_at: context.soon, state: :done}, context.options)
    end

    test "a task that is cancelled is not in its day", context do
      task = plan!(context)
      assert :ok = Tasks.cancel_task(task, context.options)

      date = Rescord.Accounts.local_date(context.organisation, context.soon)
      assert {:ok, []} = Tasks.day(date, context.options)
    end
  end
end
