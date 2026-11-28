defmodule Rescord.HealthCareTest do
  @moduledoc """
  The sanity checks of the care and of the assistant (ADR 0114, issue 38,
  C1 to C5), the fixes at their source (F3 and F4), and the part of the
  first page of an organisation that shows what they find.

  Each test creates an organisation, so the tests do not run beside others.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Health, Journal, Repo, Ruby, Tasks}
  alias Rescord.Health.Checks

  require Ash.Query

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {admin_member, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: administrator, tenant: organisation]

    {:ok,
     root: root,
     organisation: organisation,
     admin_member: admin_member,
     administrator: administrator,
     member: member,
     options: options,
     today: Accounts.today(organisation),
     biscuit: resident!(lists, options),
     schema: "org_" <> organisation.id}
  end

  defp check(check, context, now \\ DateTime.utc_now()) do
    organisation = Accounts.organisation_of(context.schema)

    {:ok, finding, _ms} =
      Health.run(check, %{now: now, organisation: organisation, prefix: context.schema})

    finding
  end

  defp sql!(context, sql, params) do
    Repo.query!(String.replace(sql, "@", ~s("#{context.schema}".)), params)
  end

  defp routine!(context, facts \\ %{}) do
    %{title: "Hay and pellets", pattern: :daily, times: [~T[08:00:00]], starts_on: context.today}
    |> Map.merge(facts)
    |> Tasks.start_routine!(context.options)
  end

  defp prescription!(context, facts) do
    entry =
      Journal.write_entry!(
        Map.merge(
          %{resident_id: context.biscuit.id, kind: :prescription, medication: "A sample drug"},
          facts
        ),
        context.options
      )

    {:ok, %{prescription: prescription}} = Journal.entry_with_facts(entry.id, context.options)
    prescription
  end

  describe "C1: routines whose tasks run out" do
    test "a routine that the job keeps up with passes", context do
      routine!(context)
      assert %{level: :ok} = check(Checks.RoutinesBehind, context)
    end

    test "a mark in the past is a fault, and a mark a day short is a note", context do
      routine = routine!(context)
      id = Ecto.UUID.dump!(routine.id)

      sql!(
        context,
        "update @routines set generated_until = now() - interval '1 hour' where id = $1",
        [id]
      )

      assert %{level: :fail, count: 1, ids: [found]} = check(Checks.RoutinesBehind, context)
      assert found == routine.id

      sql!(
        context,
        "update @routines set generated_until = now() + interval '2 days' where id = $1",
        [id]
      )

      assert %{level: :note, count: 1} = check(Checks.RoutinesBehind, context)
    end

    test "a paused, ended or removed routine is not checked", context do
      paused = routine!(context)
      Tasks.pause_routine!(paused, context.options)

      ended =
        routine!(context, %{
          ends_on: Date.add(context.today, -1),
          starts_on: Date.add(context.today, -3)
        })

      for routine <- [paused, ended] do
        sql!(
          context,
          "update @routines set generated_until = now() - interval '1 day' where id = $1",
          [
            Ecto.UUID.dump!(routine.id)
          ]
        )
      end

      assert %{level: :ok} = check(Checks.RoutinesBehind, context)
    end
  end

  describe "C2 and F4: a routine of a prescription ends with it" do
    test "a new routine of a prescription takes its last day", context do
      last = Date.add(context.today, 2)
      prescription = prescription!(context, %{starts_on: context.today, ends_on: last})

      routine = routine!(context, %{title: "Medicate", prescription_id: prescription.id})
      assert routine.ends_on == last

      later =
        routine!(context, %{
          title: "Medicate",
          prescription_id: prescription.id,
          ends_on: Date.add(last, 9)
        })

      assert later.ends_on == last

      earlier =
        routine!(context, %{
          title: "Medicate",
          prescription_id: prescription.id,
          ends_on: context.today
        })

      assert earlier.ends_on == context.today
    end

    test "no task after the last day, though the routine says no end", context do
      last = Date.add(context.today, 1)
      prescription = prescription!(context, %{starts_on: context.today, ends_on: last})
      routine = routine!(context, %{title: "Medicate", prescription_id: prescription.id})

      # As a routine from before the fix: no end.
      sql!(context, "update @routines set ends_on = null where id = $1", [
        Ecto.UUID.dump!(routine.id)
      ])

      # The job runs again from the day after: it would make the tasks of
      # the days after.
      sql!(
        context,
        "update @routines set generated_until = now() + interval '2 days' where id = $1",
        [Ecto.UUID.dump!(routine.id)]
      )

      Tasks.generate(context.organisation)

      {:ok, tasks} = Tasks.tasks(context.options)

      days =
        tasks
        |> Enum.filter(&(&1.routine_id == routine.id))
        |> Enum.map(&Accounts.local_date(context.organisation, &1.due_at))

      assert days != []
      assert Enum.all?(days, &(Date.compare(&1, last) != :gt))
    end

    test "a routine that outlives its ended prescription is a fault", context do
      prescription =
        prescription!(context, %{
          starts_on: Date.add(context.today, -5),
          ends_on: Date.add(context.today, -1)
        })

      routine =
        routine!(context, %{
          title: "Medicate",
          prescription_id: prescription.id,
          starts_on: Date.add(context.today, -5)
        })

      assert %{level: :ok} = check(Checks.RoutineAfterPrescription, context)

      sql!(context, "update @routines set ends_on = null where id = $1", [
        Ecto.UUID.dump!(routine.id)
      ])

      assert %{level: :fail, ids: [found]} = check(Checks.RoutineAfterPrescription, context)
      assert found == routine.id
    end
  end

  describe "C3: medication tasks" do
    test "a due task whose prescription is gone is a fault", context do
      task =
        Tasks.plan_task!(
          %{
            title: "Medicate",
            due_at: DateTime.add(DateTime.utc_now(), 3_600),
            prescription_id: Ecto.UUID.generate()
          },
          context.options
        )

      assert %{level: :fail, ids: [found]} = check(Checks.DoseTasks, context)
      assert found == task.id
    end

    test "a medication task more than 12 hours late is a note", context do
      prescription = prescription!(context, %{})

      Tasks.plan_task!(
        %{
          title: "Medicate",
          due_at: DateTime.add(DateTime.utc_now(), -13, :hour),
          prescription_id: prescription.id
        },
        context.options
      )

      assert %{level: :note, count: 1} = check(Checks.DoseTasks, context)
    end

    test "the first page shows the task to the people who can skip it", context do
      task =
        Tasks.plan_task!(
          %{
            title: "Medicate",
            due_at: DateTime.add(DateTime.utc_now(), 3_600),
            prescription_id: Ecto.UUID.generate()
          },
          context.options
        )

      {:ok, _, member} =
        Accounts.organisation_for(context.administrator, context.organisation.short_name)

      role = Accounts.role_in(context.administrator, member)

      assert {:ok, %{rows: [%{kind: :dose_task_blocked, record: record}], total: 1}} =
               Health.attention(role, context.options)

      assert record.id == task.id
    end
  end

  describe "C4 and C5: the assistant" do
    setup context do
      conversation =
        Ash.Seed.seed!(
          Ruby.Conversation,
          %{owner_id: context.administrator.id, last_message_at: DateTime.utc_now()},
          tenant: context.organisation
        )

      {:ok, conversation: conversation}
    end

    defp message!(context, values) do
      Ash.Seed.seed!(
        Ruby.Message,
        Map.merge(
          %{conversation_id: context.conversation.id, owner_id: context.administrator.id},
          values
        ),
        tenant: context.organisation
      )
    end

    test "a reply that stopped, and a message with no reply", context do
      assert %{level: :ok} = check(Checks.RubyReplies, context)
      long_ago = DateTime.add(DateTime.utc_now(), -4, :hour)

      said =
        message!(context, %{
          source: :user,
          text: "Hello",
          inserted_at: long_ago,
          updated_at: long_ago
        })

      reply =
        message!(context, %{
          source: :ruby,
          state: :streaming,
          response_to_id: said.id,
          inserted_at: long_ago,
          updated_at: long_ago
        })

      assert %{level: :fail, ids: [found]} = check(Checks.RubyReplies, context)
      assert found == reply.id

      alone =
        message!(context, %{
          source: :user,
          text: "Hello again",
          inserted_at: long_ago,
          updated_at: long_ago
        })

      assert %{level: :fail, count: 2} = check(Checks.RubyReplies, context)

      # The job of the assistant ends both, and the conversation takes a
      # message again.
      assert %{hung: 2} = tidy(context)
      assert %{level: :ok} = check(Checks.RubyReplies, context)

      assert %{state: :failed, reason: :unknown} =
               Ash.get!(Ruby.Message, reply.id, tenant: context.organisation, authorize?: false)

      assert [%{state: :failed}] =
               Ruby.Message
               |> Ash.Query.filter(response_to_id == ^alone.id)
               |> Ash.read!(tenant: context.organisation, authorize?: false)
    end

    test "a reply that writes still is not ended", context do
      said = message!(context, %{source: :user, text: "Hello"})
      message!(context, %{source: :ruby, state: :streaming, response_to_id: said.id})
      assert %{level: :ok} = check(Checks.RubyReplies, context)
      assert %{hung: 0} = tidy(context)
    end

    test "a conversation after its days is a fault, and the hourly work deletes it", context do
      old =
        Ash.Seed.seed!(
          Ruby.Conversation,
          %{
            owner_id: context.administrator.id,
            last_message_at: DateTime.add(DateTime.utc_now(), -91, :day)
          },
          tenant: context.organisation
        )

      assert %{level: :fail, ids: [found]} = check(Checks.RubyRetention, context)
      assert found == old.id

      assert %{old: 1} = tidy(context)
      assert %{level: :ok} = check(Checks.RubyRetention, context)

      assert Ash.get(Ruby.Conversation, context.conversation.id,
               tenant: context.organisation,
               authorize?: false
             )
             |> elem(0) == :ok
    end
  end

  describe "F3: the last member who can change the members" do
    test "keeps a role with that power", context do
      member_role =
        Accounts.roles!(actor: context.root, tenant: context.organisation)
        |> Enum.find(&(&1.key == :member))

      assert {:error, %Ash.Error.Invalid{} = error} =
               Accounts.set_member_role(context.admin_member, member_role.id,
                 actor: context.root,
                 tenant: context.organisation
               )

      assert Accounts.error_messages(error) == [
               "Role is the last member who can change the members, and stays one"
             ]

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.make_member(context.admin_member,
                 actor: context.root,
                 tenant: context.organisation
               )
    end
  end

  defp tidy(context), do: Rescord.Ruby.Workers.Tidy.tidy(context.organisation, DateTime.utc_now())
end
