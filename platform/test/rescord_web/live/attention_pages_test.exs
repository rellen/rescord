defmodule RescordWeb.AttentionPagesTest do
  @moduledoc """
  Holds the first page of an organisation (ADR 0065): it says what needs
  somebody now, each row leads to the page of its record, a part says how
  many more there are, a role sees what it can act on, the page says so
  when there is nothing, it reads again by itself, and it still leads to
  each part of the organisation.

  The tests find what a person finds (ADR 0107): the region "Needs
  attention", a part by its heading and its number, a row by its words.
  `Rescord.AttentionTest` holds what is in each part.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render: 1]
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

  defp open(context, user), do: build_conn() |> sign_in(user) |> visit(context.path)

  # A task that is due at a time of a day of the organisation.
  defp task!(context, title, date, time, more \\ %{}) do
    {:ok, due_at} =
      Accounts.local_instant(context.organisation, "#{Date.to_iso8601(date)}T#{time}")

    Tasks.plan_task!(Map.merge(%{title: title, due_at: due_at}, more), context.options)
  end

  defp attention, do: main() |> region("Needs attention")
  defp summary, do: attention() |> status()

  # A part is named by its heading, which ends with how many there are.
  defp part(title), do: attention() |> region(~r/^#{Regex.escape(title)} \d+$/)

  # A row of a part, by the words that it starts with.
  defp thing(title, words), do: part(title) |> item(~r/^#{Regex.escape(words)}\b/)

  # The rows of a part, each as the words of its link.
  defp rows(session, title), do: names(session, part(title) |> item(~r/./) |> link(~r/./))

  defp state(session, thing, kind, words),
    do: within(session, thing, &assert_has(&1, "[data-state=#{kind}]", text: words))

  test "says that nothing needs attention, and what it looks for", context do
    resident!(context.lists, context.options)

    open(context, context.member)
    |> assert_has(summary(), text: "Nothing needs attention now")
    |> state(summary(), "ok", "Nothing needs attention now")
    |> assert_has(attention(), text: "shows a change at once")
    |> refute_has(attention() |> region(~r/./))
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

    session = open(context, context.member)
    assert_has(session, summary(), text: "5 things need attention now.")

    # A task: its page is the page of the tasks, at the row of the task.
    shed = thing("Tasks", "Clean the shed")
    assert href(session, shed |> link("Clean the shed")) == "/o/#{short}/tasks#task-#{overdue.id}"

    session
    |> assert_has(attention() |> region("Tasks 1"))
    |> state(shed, "alert", "Overdue")
    |> assert_has(shed, text: "For Biscuit")
    |> assert_has(shed, text: "8:00 am")
    |> assert_has(shed, text: to_string(context.member.email))

    # An item: each fault is a state, with the words of the inventory.
    meadow_hay = thing("Stock", "Meadow hay")
    assert href(session, meadow_hay |> link("Meadow hay")) == "/o/#{short}/inventory/#{hay.id}"

    session
    |> state(meadow_hay, "alert", "Order more")
    |> state(meadow_hay, "info", "Has stock that expires soon")
    |> assert_has(meadow_hay, text: "3 bag in stock")

    # The residents: the one that is late back, then the one that is expected.
    assert rows(session, "Residents") == ["Biscuit", "Clover"]

    assert href(session, thing("Residents", "Biscuit") |> link("Biscuit")) ==
             "/o/#{short}/residents/#{biscuit.id}"

    assert href(session, thing("Residents", "Clover") |> link("Clover")) ==
             "/o/#{short}/residents/#{clover.id}"

    session
    |> state(thing("Residents", "Biscuit"), "alert", "Late back")
    |> assert_has(thing("Residents", "Biscuit"), text: "At the clinic")
    |> state(thing("Residents", "Clover"), "none", "Expected")

    # A location over its capacity.
    east = thing("Housing", "East 1")
    assert href(session, east |> link("East 1")) == "/o/#{short}/housing/#{pen.id}"

    session
    |> state(east, "alert", "Over its capacity")
    |> assert_has(east, text: "2 residents, room for 1")

    # Each part has a link to its page.
    assert href(session, part("Tasks") |> link("All the tasks of today")) == "/o/#{short}/tasks"
    assert href(session, part("Stock") |> link("The whole inventory")) == "/o/#{short}/inventory"

    assert href(session, part("Residents") |> link("All the residents")) ==
             "/o/#{short}/residents"

    assert href(session, part("Housing") |> link("The whole housing")) == "/o/#{short}/housing"

    # A row leads to a page that has the row of its fragment.
    build_conn()
    |> sign_in(context.member)
    |> visit("/o/#{short}/tasks")
    |> assert_has("#task-#{overdue.id}", text: "Clean the shed")
  end

  test "says when a task of today is due, and when a task of an earlier day was", context do
    task!(context, "A late task", context.today, "23:59")
    task!(context, "An old task", Date.add(context.today, -3), "07:30")
    session = open(context, context.member)

    assert rows(session, "Tasks") == ["An old task", "A late task"]

    session
    |> assert_has(thing("Tasks", "A late task"), text: "Today, 11:59 pm")
    |> assert_has(thing("Tasks", "A late task"), text: "Anybody")
    |> assert_has(thing("Tasks", "An old task"),
      text: "#{RescordWeb.ResidentWords.date(Date.add(context.today, -3))}, 7:30 am"
    )
  end

  test "shows the first rows of a long part, and says how many there are", context do
    for number <- 1..10 do
      task!(context, "Task #{number}", Date.add(context.today, -1), "08:#{10 + number}")
    end

    session = open(context, context.member)

    assert rows(session, "Tasks") == Enum.map(1..8, &"Task #{&1}")

    session
    |> assert_has(attention() |> region("Tasks 10"))
    |> assert_has(part("Tasks"), text: "These are the first 8 of 10.")
    |> assert_has(summary(), text: "10 things need attention now.")
  end

  test "shows the transfers and the partner requests to a person who can answer", context do
    short = context.organisation.short_name
    banksia = organisation!(context.root, "Banksia Rise")
    {_, banksia_admin} = member!(banksia, :administrator, context.root)

    {:ok, asked} = Transfers.ask_partner(banksia, short, actor: banksia_admin)

    session = open(context, context.administrator)
    request = thing("Transfers and partners", "Banksia Rise")

    assert href(session, request |> link("Banksia Rise")) ==
             "/o/#{short}/partners#partnership-#{asked.id}"

    session
    |> assert_has(request, text: "Asks to be a partner")
    |> assert_has(summary(), text: "1 thing needs attention now.")

    {:ok, _} = Transfers.accept_partner(asked, actor: context.administrator)
    pip = resident!(lists!(banksia, context.root), actor: banksia_admin, tenant: banksia)

    {:ok, sent} =
      Transfers.send_transfer(
        %{organisation_id: banksia.id, partner_id: context.organisation.id, resident_id: pip.id},
        actor: banksia_admin
      )

    session = open(context, context.administrator)
    transfer = thing("Transfers and partners", "Transfer of Biscuit")

    assert href(session, transfer |> link("Transfer of Biscuit")) ==
             "/o/#{short}/transfers#transfer-#{sent.id}"

    session
    |> assert_has(transfer, text: "Waits for an answer")
    |> assert_has(transfer, text: "From Banksia Rise")

    # The pages that the two rows lead to have the rows of the fragments.
    conn = build_conn() |> sign_in(context.administrator)
    conn |> visit("/o/#{short}/transfers") |> assert_has("#transfer-#{sent.id}")
    conn |> visit("/o/#{short}/partners") |> assert_has("#partnership-#{asked.id}")

    # A member cannot answer, and a root user can.
    open(context, context.member) |> refute_has(part("Transfers and partners"))
    open(context, context.root) |> assert_has(transfer)
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

    open(context, context.member)
    |> assert_has(part("Tasks"))
    |> assert_has(part("Stock"))

    open(context, feeder)
    |> assert_has(part("Tasks"))
    |> refute_has(part("Stock"))
    |> assert_has(summary(), text: "1 thing needs attention now.")

    # A role that only reads opens the pages, and nothing needs it here.
    open(context, reader)
    |> refute_has(attention() |> region(~r/./))
    |> assert_has(summary(), text: "Nothing needs attention now")
  end

  test "shows at once what another member did, and reads again by its clock", context do
    session = open(context, context.member)
    assert_has(session, summary(), text: "Nothing needs attention now")

    # The page hears of the task, and reads again (ADR 0096).
    task = task!(context, "Clean the shed", Date.add(context.today, -1), "08:00")

    session
    |> assert_has(thing("Tasks", "Clean the shed"))
    |> assert_has(summary(), text: "1 thing needs attention now.")

    {:ok, _} = Tasks.complete_task(task, %{}, context.options)

    session
    |> refute_has(part("Tasks"))
    |> assert_has(summary(), text: "Nothing needs attention now")

    # A change of another part of the organisation too: the stock.
    Inventory.add_item!(%{name: "Meadow hay", reorder_level: 20}, context.admin)
    assert_has(session, thing("Stock", "Meadow hay"))

    # The clock still reads: the time alone makes a task overdue. A message
    # that the page does not know changes nothing.
    session
    |> unwrap(&tell(&1, :read_again))
    |> assert_has(part("Stock"))
    |> unwrap(&tell(&1, :something_else))
    |> assert_has(summary(), text: "1 thing needs attention now.")
  end

  test "shows the routines and the doses that a sanity check finds (ADR 0114)", context do
    short = context.organisation.short_name
    tomorrow = Date.add(context.today, 1)

    routine =
      Tasks.start_routine!(
        %{
          title: "Hay and pellets",
          pattern: :daily,
          times: [~T[08:00:00]],
          starts_on: context.today
        },
        context.admin
      )

    # The job fell behind: its tasks run out before now.
    Rescord.Repo.query!(
      "update \"org_#{context.organisation.id}\".routines " <>
        "set generated_until = now() - interval '1 hour' where id = $1",
      [Ecto.UUID.dump!(routine.id)]
    )

    # A medication task whose prescription is not there.
    dose =
      task!(context, "Medicate Biscuit", tomorrow, "09:00", %{
        prescription_id: Ecto.UUID.generate()
      })

    session = open(context, context.administrator)
    care = "Routines and doses to put right"
    assert rows(session, care) == ["Hay and pellets", "Medicate Biscuit"]

    hay = thing(care, "Hay and pellets")

    assert href(session, hay |> link("Hay and pellets")) ==
             "/o/#{short}/routines/#{routine.id}/edit"

    state(session, hay, "alert", "Its tasks run out")

    medicate = thing(care, "Medicate Biscuit")

    assert href(session, medicate |> link("Medicate Biscuit")) ==
             "/o/#{short}/tasks#task-#{dose.id}"

    state(session, medicate, "alert", "Its prescription is gone")

    assert href(session, part(care) |> link("All the routines")) == "/o/#{short}/routines"

    # A member cannot revise a routine, and sees only the task.
    assert rows(open(context, context.member), care) == ["Medicate Biscuit"]
  end

  test "still leads to each part of the organisation", context do
    short = context.organisation.short_name
    session = open(context, context.member)
    parts = main() |> navigation("The parts of Wattle Creek")

    hrefs = session |> all(parts |> link(~r/./)) |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))

    for part <- ~w(tasks routines residents groups housing inventory lists members roles
                   transfers partners settings export) do
      assert "/o/#{short}/#{part}" in hrefs
    end
  end

  test "has words for each part and for each fault of the stock" do
    assert AttentionComponents.parts() == [
             :tasks,
             :inventory,
             :residents,
             :housing,
             :transfers,
             :privacy,
             :care
           ]

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

  # Sends the page a message, as its clock or its PubSub would.
  defp tell(view, message) do
    send(view.pid, message)
    render(view)
  end
end
