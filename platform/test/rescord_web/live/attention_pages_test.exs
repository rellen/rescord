defmodule RescordWeb.AttentionPagesTest do
  @moduledoc """
  Holds the first page of an organisation (ADR 0065): it says what needs
  somebody now, each row leads to the page of its record, a part says how
  many more there are, a role sees what it can act on, the page says so
  when there is nothing, it reads again by itself, and it still leads to
  each part of the organisation.

  `Rescord.AttentionTest` holds what is in each part.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Inventory, Locations, Residents, Tasks, Transfers}
  alias RescordWeb.{AttentionComponents, InventoryWords}

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
     today: Accounts.today(organisation),
     path: ~p"/o/#{organisation.short_name}"}
  end

  defp open(context, user) do
    {:ok, view, _html} = build_conn() |> sign_in(user) |> live(context.path)
    view
  end

  # A task that is due at a time of a day of the organisation.
  defp task!(context, title, date, time, more \\ %{}) do
    {:ok, due_at} =
      Accounts.local_instant(context.organisation, "#{Date.to_iso8601(date)}T#{time}")

    Tasks.plan_task!(Map.merge(%{title: title, due_at: due_at}, more), context.options)
  end

  # The rows of a part, each as the words of its link.
  defp rows(view, part) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#attention-#{part} ul[data-attention] > li > a")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  test "says that nothing needs attention, and what it looks for", context do
    resident!(context.lists, context.options)
    view = open(context, context.member)

    assert has_element?(view, "#attention h2", "Needs attention")
    assert has_element?(view, "#attention-summary[role=status]", "Nothing needs attention now")
    assert has_element?(view, "#attention-summary span[data-state=ok]")
    assert has_element?(view, "#attention-nothing", "shows a change at once")
    refute has_element?(view, "ul[data-attention]")
  end

  test "shows each thing that needs somebody, with a link to its record", context do
    short = context.organisation.short_name
    yesterday = Date.add(context.today, -1)

    biscuit = resident!(context.lists, context.options, %{name: "Biscuit"})

    overdue =
      task!(context, "Clean the shed", yesterday, "08:00", %{
        resident_ids: [biscuit.id],
        assignee_ids: [context.member.id]
      })

    hay =
      Inventory.add_item!(
        %{name: "Meadow hay", unit_id: context.lists.unit.bag, reorder_level: 20},
        context.admin
      )

    Inventory.receive_lot!(
      %{item_id: hay.id, quantity: 3, expires_on: Date.add(context.today, 5)},
      context.options
    )

    clover =
      resident!(context.lists, context.options, %{
        name: "Clover",
        arrival_kind: nil,
        arrived_on: nil
      })

    {:ok, _} =
      Residents.start_absence(
        %{resident_id: biscuit.id, reason: "At the clinic", expected_back_on: yesterday},
        context.options
      )

    pen = Locations.add_location!(%{name: "East 1", capacity: 1}, context.admin)

    for name <- ["Fern", "Hazel"] do
      resident = resident!(context.lists, context.options, %{name: name})
      {:ok, _} = Locations.settle({:resident, resident.id}, pen.id, context.options)
    end

    view = open(context, context.member)

    assert has_element?(view, "#attention-summary", "5 things need attention now.")

    # A task: its page is the page of the tasks, at the row of the task.
    assert has_element?(
             view,
             ~s(#attention-task-#{overdue.id} a[href="/o/#{short}/tasks#task-#{overdue.id}"]),
             "Clean the shed"
           )

    assert has_element?(view, "#attention-task-#{overdue.id} span[data-state=alert]", "Overdue")
    assert has_element?(view, "#attention-task-#{overdue.id} small", "For Biscuit")
    assert has_element?(view, "#attention-task-#{overdue.id} small", "8:00 am")

    assert has_element?(
             view,
             "#attention-task-#{overdue.id} small",
             to_string(context.member.email)
           )

    assert has_element?(view, "#attention-tasks h3", "Tasks")
    assert has_element?(view, "#attention-tasks h3 small", "1")

    # An item: each fault is a state, with the words of the inventory.
    assert has_element?(
             view,
             ~s(#attention-stock-#{hay.id} a[href="/o/#{short}/inventory/#{hay.id}"]),
             "Meadow hay"
           )

    assert has_element?(view, "#attention-stock-#{hay.id} span[data-state=alert]", "Order more")

    assert has_element?(
             view,
             "#attention-stock-#{hay.id} span[data-state=info]",
             "Has stock that expires soon"
           )

    assert has_element?(view, "#attention-stock-#{hay.id} small", "3 bag in stock")

    # The residents: the one that is late back, then the one that is expected.
    assert rows(view, "residents") == ["Biscuit", "Clover"]

    assert has_element?(
             view,
             ~s(#attention-late-back-#{biscuit.id} a[href="/o/#{short}/residents/#{biscuit.id}"])
           )

    assert has_element?(view, "#attention-late-back-#{biscuit.id}", "Late back")
    assert has_element?(view, "#attention-late-back-#{biscuit.id} small", "At the clinic")

    assert has_element?(
             view,
             ~s(#attention-expected-#{clover.id} a[href="/o/#{short}/residents/#{clover.id}"])
           )

    assert has_element?(view, "#attention-expected-#{clover.id}", "Expected")

    # A location over its capacity.
    assert has_element?(
             view,
             ~s(#attention-over-capacity-#{pen.id} a[href="/o/#{short}/housing/#{pen.id}"]),
             "East 1"
           )

    assert has_element?(view, "#attention-over-capacity-#{pen.id}", "Over its capacity")
    assert has_element?(view, "#attention-over-capacity-#{pen.id} small", "2 of 1 residents")

    # Each part has a link to its page.
    assert has_element?(view, ~s(#attention-tasks a[href="/o/#{short}/tasks"]))
    assert has_element?(view, ~s(#attention-inventory a[href="/o/#{short}/inventory"]))
    assert has_element?(view, ~s(#attention-residents a[href="/o/#{short}/residents"]))
    assert has_element?(view, ~s(#attention-housing a[href="/o/#{short}/housing"]))

    # A row leads to a page that has the row of its fragment.
    {:ok, tasks, _html} = live(build_conn() |> sign_in(context.member), "/o/#{short}/tasks")
    assert has_element?(tasks, "#task-#{overdue.id}")
  end

  test "says when a task of today is due, and when a task of an earlier day was", context do
    late = task!(context, "A late task", context.today, "23:59")
    old = task!(context, "An old task", Date.add(context.today, -3), "07:30")
    view = open(context, context.member)

    assert rows(view, "tasks") == ["An old task", "A late task"]
    assert has_element?(view, "#attention-task-#{late.id} small", "Today, 11:59 pm")

    assert has_element?(
             view,
             "#attention-task-#{old.id} small",
             "#{RescordWeb.ResidentWords.date(Date.add(context.today, -3))}, 7:30 am"
           )

    assert has_element?(view, "#attention-task-#{late.id} small", "Anybody")
  end

  test "shows the first rows of a long part, and says how many there are", context do
    for number <- 1..10 do
      task!(context, "Task #{number}", Date.add(context.today, -1), "08:#{10 + number}")
    end

    view = open(context, context.member)

    assert rows(view, "tasks") == Enum.map(1..8, &"Task #{&1}")
    assert has_element?(view, "#attention-tasks h3 small", "10")
    assert has_element?(view, "#attention-tasks p", "These are the first 8 of 10.")
    assert has_element?(view, "#attention-summary", "10 things need attention now.")
  end

  test "shows the transfers and the partner requests to a person who can answer", context do
    short = context.organisation.short_name
    banksia = organisation!(context.root, "Banksia Rise")
    {_, banksia_admin} = member!(banksia, :administrator, context.root)

    {:ok, asked} = Transfers.ask_partner(banksia, short, actor: banksia_admin)

    view = open(context, context.administrator)

    assert has_element?(
             view,
             ~s(#attention-partner-request-#{asked.id} ) <>
               ~s(a[href="/o/#{short}/partners#partnership-#{asked.id}"]),
             "Banksia Rise"
           )

    assert has_element?(view, "#attention-partner-request-#{asked.id}", "Asks to be a partner")
    assert has_element?(view, "#attention-summary", "1 thing needs attention now.")

    {:ok, _} = Transfers.accept_partner(asked, actor: context.administrator)
    pip = resident!(lists!(banksia, context.root), actor: banksia_admin, tenant: banksia)

    {:ok, sent} =
      Transfers.send_transfer(
        %{organisation_id: banksia.id, partner_id: context.organisation.id, resident_id: pip.id},
        actor: banksia_admin
      )

    view = open(context, context.administrator)

    assert has_element?(
             view,
             ~s(#attention-transfer-#{sent.id} a[href="/o/#{short}/transfers#transfer-#{sent.id}"]),
             "Transfer of Biscuit"
           )

    assert has_element?(view, "#attention-transfer-#{sent.id}", "Waits for an answer")
    assert has_element?(view, "#attention-transfer-#{sent.id} small", "From Banksia Rise")

    # The pages that the two rows lead to have the rows of the fragments.
    conn = build_conn() |> sign_in(context.administrator)
    {:ok, transfers, _html} = live(conn, "/o/#{short}/transfers")
    assert has_element?(transfers, "#transfer-#{sent.id}")
    {:ok, partners, _html} = live(conn, "/o/#{short}/partners")
    assert has_element?(partners, "#partnership-#{asked.id}")

    # A member cannot answer, and a root user can.
    refute has_element?(open(context, context.member), "#attention-transfers")
    assert has_element?(open(context, context.root), "#attention-transfer-#{sent.id}")
  end

  test "shows a role only what it can act on", context do
    task!(context, "Clean the shed", Date.add(context.today, -1), "08:00")

    hay = Inventory.add_item!(%{name: "Meadow hay", reorder_level: 20}, context.admin)
    Inventory.receive_lot!(%{item_id: hay.id, quantity: 3}, context.options)

    {:ok, reader_role} = Accounts.define_role(%{name: "Reader", powers: []}, context.admin)
    {:ok, feeder_role} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)

    [reader, feeder] =
      for role <- [reader_role, feeder_role] do
        {_, user} = member!(context.organisation, :member, context.administrator)

        {:ok, _organisation, member} =
          Accounts.organisation_for(user, context.organisation.short_name)

        {:ok, _member} = Accounts.set_member_role(member, role.id, context.admin)
        user
      end

    view = open(context, context.member)
    assert has_element?(view, "#attention-tasks")
    assert has_element?(view, "#attention-inventory")

    view = open(context, feeder)
    assert has_element?(view, "#attention-tasks")
    refute has_element?(view, "#attention-inventory")
    assert has_element?(view, "#attention-summary", "1 thing needs attention now.")

    # A role that only reads opens the pages, and nothing needs it here.
    view = open(context, reader)
    refute has_element?(view, "ul[data-attention]")
    assert has_element?(view, "#attention-summary", "Nothing needs attention now")
  end

  test "shows at once what another member did, and reads again by its clock", context do
    view = open(context, context.member)
    assert has_element?(view, "#attention-summary", "Nothing needs attention now")

    # The page hears of the task, and reads again (ADR 0096).
    task = task!(context, "Clean the shed", Date.add(context.today, -1), "08:00")
    assert has_element?(view, "#attention-task-#{task.id}", "Clean the shed")
    assert has_element?(view, "#attention-summary", "1 thing needs attention now.")

    {:ok, _} = Tasks.complete_task(task, %{}, context.options)
    refute has_element?(view, "#attention-task-#{task.id}")
    assert has_element?(view, "#attention-summary", "Nothing needs attention now")

    # A change of another part of the organisation too: the stock.
    Inventory.add_item!(%{name: "Meadow hay", reorder_level: 20}, context.admin)
    assert has_element?(view, "#attention-inventory")
    assert render(view) =~ "Meadow hay"

    # The clock still reads: the time alone makes a task overdue.
    send(view.pid, :read_again)
    assert has_element?(view, "#attention-inventory")

    # A message that the page does not know changes nothing.
    send(view.pid, :something_else)
    assert has_element?(view, "#attention-summary", "1 thing needs attention now.")
  end

  test "still leads to each part of the organisation", context do
    short = context.organisation.short_name
    view = open(context, context.member)

    assert has_element?(
             view,
             "nav[aria-labelledby=parts-heading] h2",
             "The parts of Wattle Creek"
           )

    for part <- ~w(tasks routines residents groups housing inventory lists members roles
                   transfers partners settings export) do
      assert has_element?(view, ~s(nav ul[data-links] a[href="/o/#{short}/#{part}"]))
    end
  end

  test "has words for each part and for each fault of the stock" do
    assert AttentionComponents.parts() == [:tasks, :inventory, :residents, :housing, :transfers]

    for fault <- InventoryWords.faults() do
      assert {words, kind} = InventoryWords.fault(fault)
      assert is_binary(words) and kind in ~w(ok alert info none)
    end

    # Each fault that the inventory knows has words.
    stock = %{below_zero: [:a], short: [:a], expired: Decimal.new(1), soon: Decimal.new(1)}
    assert Inventory.faults(stock) == InventoryWords.faults()

    # The filter of the inventory page has a choice for each fault, and one
    # for each item with a fault (ADR 0088). A value names its fault.
    assert Enum.sort(InventoryWords.fault_choices()) ==
             Enum.sort([:any | InventoryWords.faults()])

    for {_words, value} <- InventoryWords.fault_options() do
      assert InventoryWords.fault_of(value) in InventoryWords.fault_choices()
    end

    assert InventoryWords.fault_of("nothing") == nil
    assert InventoryWords.fault_of(nil) == nil
  end
end
