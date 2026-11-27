defmodule Rescord.AttentionTest do
  @moduledoc """
  Holds what needs somebody now in an organisation (ADR 0065): what each
  domain gives, in which order, that a part has a limit and a total, that
  "today" is a day of the organisation, and the two rules of who sees a
  row: a person sees what they can read, and what their role can act on.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Attention, Inventory, Locations, Residents, Tasks, Transfers}

  # Noon of 10 March 2026 in Brisbane, which is ten hours ahead of UTC.
  @now ~U[2026-03-10 02:00:00Z]

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists,
     admin: [actor: administrator, tenant: organisation],
     options: [actor: member, tenant: organisation],
     today: Accounts.today(organisation)}
  end

  # The parts that a user sees, with the role that the user has.
  defp parts(context, user, now \\ @now) do
    role =
      case Accounts.organisation_for(user, context.organisation.short_name) do
        {:ok, _organisation, member} -> Accounts.role_in(user, member)
        :error -> nil
      end

    Attention.parts(context.organisation, actor: user, role: role, now: now)
  end

  defp task!(context, title, local) do
    {:ok, due_at} = Accounts.local_instant(context.organisation, local)
    Tasks.plan_task!(%{title: title, due_at: due_at}, context.options)
  end

  defp hay!(context, attributes \\ %{}) do
    %{name: "Meadow hay", unit_id: context.lists.unit.bag}
    |> Map.merge(attributes)
    |> Inventory.add_item!(context.admin)
  end

  defp lot!(context, item, facts) do
    %{item_id: item.id, quantity: 10}
    |> Map.merge(facts)
    |> Inventory.receive_lot!(context.options)
  end

  # A member with a role that has only the powers of `powers`.
  defp member_with!(context, name, powers) do
    {:ok, role} = Accounts.define_role(%{name: name, powers: powers}, context.admin)
    {_, user} = member!(context.organisation, :member, context.administrator)

    {:ok, _organisation, member} =
      Accounts.organisation_for(user, context.organisation.short_name)

    {:ok, _member} = Accounts.set_member_role(member, role.id, context.admin)
    user
  end

  test "an organisation where nothing needs somebody has no part", context do
    resident!(context.lists, context.options)
    task!(context, "A task of tomorrow", "2026-03-11T08:00")
    lot!(context, hay!(context), %{})

    assert parts(context, context.member) == []
    assert parts(context, context.administrator) == []
    assert Attention.total([]) == 0
  end

  describe "the tasks" do
    test "are the ones that are overdue and the ones of today, the oldest first", context do
      evening = task!(context, "Evening feed", "2026-03-10T18:00")
      yesterday = task!(context, "Clean the shed", "2026-03-09T08:00")
      morning = task!(context, "Morning feed", "2026-03-10T09:00")
      task!(context, "A task of tomorrow", "2026-03-11T00:30")

      done = task!(context, "A task that is done", "2026-03-10T07:00")
      {:ok, _} = Tasks.complete_task(done, %{}, context.options)

      assert [%{part: :tasks, total: 3, rows: rows}] = parts(context, context.member)

      assert Enum.map(rows, &{&1.kind, &1.record.id, &1.phase}) == [
               {:task, yesterday.id, :overdue},
               {:task, morning.id, :overdue},
               {:task, evening.id, :due}
             ]
    end

    test "of today are the ones of the day of the organisation, and not of UTC", context do
      # 23:30 in Brisbane is 13:30 UTC, and half past midnight there is still
      # the day before in UTC.
      late = task!(context, "A late task of today", "2026-03-10T23:30")
      task!(context, "An early task of tomorrow", "2026-03-11T00:30")

      assert [%{part: :tasks, rows: [%{record: %{id: id}, phase: :due}]}] =
               parts(context, context.member)

      assert id == late.id
    end

    test "have a limit, and a total that counts each one", context do
      for hour <- 1..11 do
        task!(context, "Task #{hour}", "2026-03-09T#{String.pad_leading("#{hour}", 2, "0")}:00")
      end

      assert [%{part: :tasks, total: 11, rows: rows}] = parts(context, context.member)
      assert length(rows) == Attention.limit()
      assert hd(rows).record.title == "Task 1"
      assert Attention.total(parts(context, context.member)) == 11
    end

    test "carry what a page shows of each: its subjects", context do
      biscuit = resident!(context.lists, context.options)
      {:ok, due_at} = Accounts.local_instant(context.organisation, "2026-03-10T09:00")

      Tasks.plan_task!(
        %{title: "Weigh Biscuit", due_at: due_at, resident_ids: [biscuit.id]},
        context.options
      )

      assert [%{rows: [%{record: task}]}] = parts(context, context.member)
      assert Tasks.subject_names(task) == ["Biscuit"]
    end
  end

  describe "the stock" do
    test "is each item with a fault, the ones that cannot wait first", context do
      # In the order of the names: Bedding, Critical care, Meadow hay, Pellets, Vitamin C.
      soon = hay!(context, %{name: "Bedding"})
      lot!(context, soon, %{expires_on: Date.add(context.today, 5)})

      expired = hay!(context, %{name: "Critical care"})
      lot!(context, expired, %{expires_on: Date.add(context.today, -1)})

      short = hay!(context, %{reorder_level: 20})
      lot!(context, short, %{})

      fine = hay!(context, %{name: "Pellets", reorder_level: 5})
      lot!(context, fine, %{expires_on: Date.add(context.today, 200)})

      shed = Locations.add_location!(%{name: "Feed shed"}, context.admin)
      below = hay!(context, %{name: "Vitamin C"})
      lot = lot!(context, below, %{quantity: 2, location_id: shed.id})

      {:ok, _} =
        Inventory.use_stock(%{lot_id: lot.id, location_id: shed.id, quantity: 3}, context.options)

      assert [%{part: :inventory, total: 4, rows: rows}] = parts(context, context.member)

      assert Enum.map(rows, &{&1.kind, &1.record.name, &1.faults}) == [
               {:stock, "Critical care", [:expired]},
               {:stock, "Meadow hay", [:short]},
               {:stock, "Vitamin C", [:below_zero]},
               {:stock, "Bedding", [:soon]}
             ]
    end
  end

  describe "the residents" do
    test "are the ones that are late back, and then the ones that are expected", context do
      resident!(context.lists, context.options, %{name: "Biscuit"})

      expected =
        resident!(context.lists, context.options, %{
          name: "Clover",
          arrival_kind: nil,
          arrived_on: nil
        })

      late = resident!(context.lists, context.options, %{name: "Fern"})
      back_soon = resident!(context.lists, context.options, %{name: "Hazel"})
      no_day = resident!(context.lists, context.options, %{name: "Juniper"})

      for {resident, day} <- [
            {late, Date.add(context.today, -2)},
            {back_soon, Date.add(context.today, 1)},
            {no_day, nil}
          ] do
        {:ok, _} =
          Residents.start_absence(
            %{resident_id: resident.id, reason: "At the clinic", expected_back_on: day},
            context.options
          )
      end

      now = DateTime.utc_now()
      assert [%{part: :residents, total: 2, rows: rows}] = parts(context, context.member, now)

      assert [
               %{kind: :late_back, record: %{name: "Fern"}, absence: %{reason: "At the clinic"}},
               %{kind: :expected, record: %{name: "Clover"}}
             ] = rows

      assert hd(rows).record.id == late.id
      assert List.last(rows).record.id == expected.id
    end

    test "that are late back are not the ones that left", context do
      fern = resident!(context.lists, context.options, %{name: "Fern"})

      {:ok, _} =
        Residents.start_absence(
          %{
            resident_id: fern.id,
            reason: "At the clinic",
            expected_back_on: Date.add(context.today, -2)
          },
          context.options
        )

      now = DateTime.utc_now()
      assert [%{part: :residents, total: 1}] = parts(context, context.member, now)

      {:ok, _} =
        Residents.record_departure(
          %{resident_id: fern.id, kind: :death, departed_on: context.today},
          context.options
        )

      assert parts(context, context.member, DateTime.utc_now()) == []
    end
  end

  describe "the housing" do
    test "is each location with more residents than its capacity", context do
      shed = Locations.add_location!(%{name: "Main shed"}, context.admin)
      Locations.add_location!(%{name: "East 1", parent_id: shed.id, capacity: 2}, context.admin)

      west =
        Locations.add_location!(%{name: "West 1", parent_id: shed.id, capacity: 1}, context.admin)

      assert parts(context, context.member) == []

      for name <- ["Fern", "Hazel"] do
        resident = resident!(context.lists, context.options, %{name: name})
        {:ok, _} = Locations.settle({:resident, resident.id}, west.id, context.options)
      end

      assert [%{part: :housing, total: 1, rows: [row]}] = parts(context, context.member)
      assert %{kind: :over_capacity, count: 2, record: %{name: "West 1", capacity: 1}} = row
      assert row.record.id == west.id
    end
  end

  describe "the transfers" do
    setup context do
      banksia = organisation!(context.root, "Banksia Rise")
      {_, banksia_admin} = member!(banksia, :administrator, context.root)
      {:ok, context |> Map.put(:banksia, banksia) |> Map.put(:banksia_admin, banksia_admin)}
    end

    test "are the partner requests and the transfers that wait for this refuge", context do
      {:ok, asked} =
        Transfers.ask_partner(context.banksia, context.organisation.short_name,
          actor: context.banksia_admin
        )

      assert [%{part: :transfers, total: 1, rows: [request]}] =
               parts(context, context.administrator)

      assert %{kind: :partner_request, record: %{id: id}} = request
      assert id == asked.id
      assert Transfers.other(request.record, context.organisation).name == "Banksia Rise"

      # A member reads the partnerships, and cannot answer: nothing waits for a member.
      assert parts(context, context.member) == []

      # The refuge that asked waits, and nothing waits for it.
      assert parts(Map.put(context, :organisation, context.banksia), context.banksia_admin) == []

      {:ok, _} = Transfers.accept_partner(asked, actor: context.administrator)
      assert parts(context, context.administrator) == []

      banksia_lists = lists!(context.banksia, context.root)

      pip =
        resident!(banksia_lists, [actor: context.banksia_admin, tenant: context.banksia], %{
          name: "Pip"
        })

      {:ok, sent} =
        Transfers.send_transfer(
          %{
            organisation_id: context.banksia.id,
            partner_id: context.organisation.id,
            resident_id: pip.id
          },
          actor: context.banksia_admin
        )

      assert [%{part: :transfers, total: 1, rows: [transfer]}] =
               parts(context, context.administrator)

      assert %{kind: :transfer, record: %{resident_name: "Pip"}} = transfer
      assert transfer.record.id == sent.id
      assert Transfers.other(transfer.record, context.organisation).name == "Banksia Rise"

      # A member has no power over the transfers: nothing waits for a member.
      assert parts(context, context.member) == []

      {:ok, _} = Transfers.accept_transfer(sent, actor: context.administrator)
      assert parts(context, context.administrator) == []
    end
  end

  describe "who sees a row" do
    setup context do
      task!(context, "Clean the shed", "2026-03-09T08:00")
      lot!(context, hay!(context, %{reorder_level: 20}), %{})

      resident!(context.lists, context.options, %{
        name: "Clover",
        arrival_kind: nil,
        arrived_on: nil
      })

      pen = Locations.add_location!(%{name: "East 1", capacity: 1}, context.admin)

      for name <- ["Fern", "Hazel"] do
        resident = resident!(context.lists, context.options, %{name: name})
        {:ok, _} = Locations.settle({:resident, resident.id}, pen.id, context.options)
      end

      :ok
    end

    test "a member and a root user see each part that they can act on", context do
      for user <- [context.member, context.administrator, context.root] do
        assert parts(context, user) |> Enum.map(& &1.part) ==
                 [:tasks, :inventory, :residents, :housing]
      end
    end

    test "a role sees only the parts that it has the power to act on", context do
      feeder = member_with!(context, "Feeder", [:tasks])
      assert [%{part: :tasks, total: 1}] = parts(context, feeder)

      keeper = member_with!(context, "Keeper", [:stock, :residents])
      assert parts(context, keeper) |> Enum.map(& &1.part) == [:inventory, :residents]

      mover = member_with!(context, "Mover", [:placements])
      assert [%{part: :housing, total: 1}] = parts(context, mover)

      # A role that only reads can act on nothing, so nothing needs it.
      reader = member_with!(context, "Reader", [])
      assert parts(context, reader) == []
    end

    test "a person sees nothing that the policies do not let them read", context do
      stranger = user!()

      # No role, and so no part.
      assert parts(context, stranger) == []

      # The role is what the caller says, and the reads are still those of
      # the person: a caller that gets the role wrong shows no record.
      for role <- [:root, :administrator] do
        assert Attention.parts(context.organisation, actor: stranger, role: role, now: @now) ==
                 []
      end
    end
  end
end
