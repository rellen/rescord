defmodule Rescord.ChangesTest do
  @moduledoc """
  Holds what a process hears when a record changes (ADR 0096): a change of
  its own organisation and of the domain that it asked for, with no
  attribute of the record, and nothing of its own writes. A sweep holds that
  each resource publishes that way.

  The test creates organisations, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Ash.Notifier.PubSub.Info
  alias Rescord.Changes
  alias Rescord.Changes.Change
  alias Rescord.{Locations, Residents, Tasks, Transfers}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     options: [actor: administrator, tenant: organisation],
     soon: DateTime.add(DateTime.utc_now(), 3600)}
  end

  # Runs `fun` in another process, as another member's page or a job would.
  defp elsewhere(fun), do: fun |> Task.async() |> Task.await(15_000)

  defp plan!(context, title \\ "Hay and pellets") do
    Tasks.plan_task!(%{title: title, due_at: context.soon}, context.options)
  end

  describe "a process that listens" do
    test "hears a create, an update and a destroy of its organisation", context do
      :ok = Changes.subscribe(context.organisation, [Tasks])

      task = elsewhere(fn -> plan!(context) end)
      id = task.id

      # A task has its subjects and its people, so more than one resource of
      # the domain says so.
      assert_receive %Change{domain: Tasks, resource: Rescord.Tasks.Task, type: :create, id: ^id}

      elsewhere(fn -> Tasks.take_task!(task, context.options) end)

      assert_receive %Change{
        domain: Tasks,
        resource: Rescord.Tasks.Task,
        action: :take,
        type: :update,
        id: ^id
      }
    end

    test "hears nothing of the process that wrote", context do
      :ok = Changes.subscribe(context.organisation, [Tasks])

      plan!(context)

      refute_receive %Change{}, 100
    end

    test "hears nothing of another organisation", context do
      other = organisation!(context.root, "Ironbark Flat")
      {_, administrator} = member!(other, :administrator, context.root)
      :ok = Changes.subscribe(other, [Tasks])

      elsewhere(fn -> plan!(context) end)
      refute_receive %Change{}, 100

      elsewhere(fn ->
        Tasks.plan_task!(
          %{title: "Count the hay", due_at: context.soon},
          actor: administrator,
          tenant: other
        )
      end)

      assert_receive %Change{domain: Tasks, type: :create}
    end

    test "hears nothing of a domain that it did not ask for", context do
      :ok = Changes.subscribe(context.organisation, [Locations])

      elsewhere(fn -> plan!(context) end)

      refute_receive %Change{}, 100
    end

    test "gets no attribute of the record", context do
      :ok = Changes.subscribe(context.organisation, [Tasks])

      elsewhere(fn -> plan!(context, "A title that must stay where it is") end)

      assert_receive %Change{resource: Rescord.Tasks.Task} = change

      assert change |> Map.from_struct() |> Map.keys() |> Enum.sort() ==
               [:action, :domain, :id, :resource, :type]

      refute inspect(change, limit: :infinity) =~ "must stay"
    end

    test "hears what a listener of a signal wrote in another domain", context do
      # The removal of a resident takes the resident off its tasks, with a
      # signal (ADR 0067). The write of the listener is an action, and it
      # says so as each action does.
      lists = lists!(context.organisation, context.root)
      resident = resident!(lists, context.options)

      Tasks.plan_task!(
        %{title: "Nail trim", due_at: context.soon, resident_ids: [resident.id]},
        context.options
      )

      :ok = Changes.subscribe(context.organisation, [Tasks])
      elsewhere(fn -> :ok = Residents.remove_resident(resident, context.options) end)

      assert_receive %Change{domain: Tasks, resource: Rescord.Tasks.TaskSubject, type: :destroy}
    end

    test "hears a write of a job, which has no actor", context do
      # The job of the routines writes the tasks with no actor and with no
      # policy check. A change does not depend on who wrote.
      Tasks.start_routine!(
        %{
          title: "Feed hay",
          pattern: :daily,
          times: [~T[08:00:00]],
          starts_on: Rescord.Accounts.today(context.organisation)
        },
        context.options
      )

      :ok = Changes.subscribe(context.organisation, [Tasks])
      later = DateTime.add(DateTime.utc_now(), 3, :day)
      elsewhere(fn -> Tasks.generate(context.organisation, later) end)

      assert_receive %Change{domain: Tasks, resource: Rescord.Tasks.Task, type: :create}
    end

    test "hears nothing of a write that was undone", context do
      :ok = Changes.subscribe(context.organisation, [Tasks])

      elsewhere(fn ->
        {:error, _error} =
          Ash.transact([Rescord.Tasks.Task], fn ->
            plan!(context)
            {:error, "no"}
          end)
      end)

      refute_receive %Change{}, 100
    end

    test "hears a shared record from each of its two organisations", context do
      other = organisation!(context.root, "Ironbark Flat")
      stranger = organisation!(context.root, "Bottlebrush Bend")

      :ok = Changes.subscribe(other, [Transfers])

      elsewhere(fn ->
        {:ok, _asked} =
          Transfers.ask_partner(context.organisation, other.short_name, actor: context.root)
      end)

      assert_receive %Change{domain: Transfers, type: :create}

      :ok = Changes.subscribe(stranger, [Transfers])
      refute_receive %Change{}, 100
    end
  end

  describe "each resource" do
    # A resource that organisations share has no tenant, so it names the
    # organisation by an attribute, or it tells no page (`quiet/0`).
    defp quiet do
      # The base lists, which a root user changes and each organisation reads.
      base_lists =
        for resource <- Ash.Domain.Info.resources(Rescord.Lists),
            match?(["Rescord", "Lists", "Base" | _name], Module.split(resource)),
            do: resource

      base_lists ++
        [
          # A page of one organisation shows none of these.
          Rescord.Accounts.User,
          Rescord.Accounts.Token,
          Rescord.Ruby.Provider,
          # The usage counts of the server, which only a root user reads.
          Rescord.Usage.Count,
          Rescord.Usage.Settings,
          # The devices and the topics of a person, and the settings of the
          # server: a person has them in no organisation, and no page of
          # another person shows them (ADR 0106).
          Rescord.Notifications.PushSubscription,
          Rescord.Notifications.NtfyTopic,
          Rescord.Notifications.Settings,
          # The privacy settings of the server, which only a root user
          # changes, and which a notice reads at each request (ADR 0105).
          Rescord.Privacy.InstanceSettings,
          # The virus scan of the server, which only a root user sets (issue 37).
          Rescord.Storage.Scan.Settings,
          # The private keys of a refuge. No page waits for one.
          Rescord.Transfers.RefugeKey,
          # What the sanity checks found, which only the root page of the
          # checks shows, and which it reads again after a run (ADR 0114).
          Rescord.Health.Result,
          # The root users who asked for the alerts of the checks: no page
          # of another person shows them (ADR 0114).
          Rescord.Health.Watcher
        ]
    end

    defp resources do
      for domain <- Application.fetch_env!(:rescord, :ash_domains),
          resource <- Ash.Domain.Info.resources(domain),
          # A version resource is not a `Rescord.Resource`: a page hears of
          # the record, and reads the versions after that.
          not String.ends_with?(inspect(resource), ".Version"),
          Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer,
          do: resource
    end

    test "sends a change through Rescord.Changes, and nothing else" do
      assert resources() != []

      for resource <- resources() do
        assert Ash.Notifier.PubSub in Ash.Resource.Info.notifiers(resource),
               "#{inspect(resource)} has no notifier"

        assert Info.module(resource) == Changes
        assert Info.prefix(resource) == Changes.prefix()
        assert is_function(Info.transform(resource), 1), "#{inspect(resource)} has no transform"

        for publication <- Info.publications(resource) do
          assert is_nil(publication.transform),
                 "a publication of #{inspect(resource)} has a transform of its own"

          assert List.last(List.wrap(publication.topic)) ==
                   Changes.key(Ash.Resource.Info.domain(resource))
        end
      end
    end

    test "publishes each create, update and destroy, unless it is quiet on purpose" do
      for resource <- resources(), resource not in quiet() do
        types =
          resource |> Info.publications() |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort()

        assert types == [:create, :destroy, :update],
               "#{inspect(resource)} does not publish each kind of action"
      end

      for resource <- quiet() do
        assert Info.publications(resource) == [], "#{inspect(resource)} is not quiet"
      end
    end
  end
end
