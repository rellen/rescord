defmodule RescordWeb.InventoryPagesTest do
  @moduledoc """
  Holds the pages of the inventory: the list of the items, the page of one
  item with its lots and what a member records there, and the suppliers.

  The tests find what a person finds (ADR 0107): an item is a row of the
  region "The items", a lot a row of the region "Stock", a movement a row
  of "What happened", and each form is in the disclosure that its summary
  names. The controls of Cinder keep their ids.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest,
    only: [
      assert_patch: 1,
      assert_redirect: 1,
      element: 2,
      live: 2,
      refute_patched: 2,
      render_async: 1,
      render_change: 2,
      render_click: 1,
      render_click: 3,
      render_submit: 3
    ]

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Inventory, Locations}
  alias RescordWeb.InventoryWords

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]
    options = [actor: member, tenant: organisation]

    shed = Locations.add_location!(%{name: "Feed shed"}, admin)
    clinic = Locations.add_location!(%{name: "Clinic room"}, admin)

    hay =
      Inventory.add_item!(
        %{name: "Meadow hay", category_id: lists.item_category.food, unit_id: lists.unit.bag},
        admin
      )

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     lists: lists,
     admin: admin,
     options: options,
     today: Accounts.today(organisation),
     shed: shed,
     clinic: clinic,
     hay: hay,
     path: ~p"/o/#{organisation.short_name}/inventory",
     item_path: ~p"/o/#{organisation.short_name}/inventory/#{hay.id}",
     conn: sign_in(context.conn, member),
     admin_conn: sign_in(build_conn(), administrator)}
  end

  # Cinder draws its rows after the first render of a page.
  defp open(conn, path), do: conn |> visit(path) |> settle()
  defp settle(session), do: unwrap(session, &render_async/1)
  defp send_form(session, button), do: session |> click_button(button) |> settle()

  defp lot!(context, facts \\ %{}) do
    %{item_id: context.hay.id, quantity: 10, location_id: context.shed.id, code: "B-1"}
    |> Map.merge(facts)
    |> Inventory.receive_lot!(context.options)
  end

  defp stock!(context) do
    {:ok, stock} = Inventory.item_stock(context.hay.id, context.options)
    stock
  end

  defp level(context), do: InventoryWords.plain(stock!(context).level)

  # The parts of the pages, and a row by the words that it starts with.
  defp items, do: main() |> region("The items")
  defp item_row(name), do: items() |> row(~r/^#{Regex.escape(name)}\b/)
  defp shown(session), do: names(session, items() |> row(~r/./) |> link(~r/./))

  defp stock, do: main() |> region("Stock")
  defp lot_row(words), do: stock() |> row(~r/^#{Regex.escape(words)}\b/)
  defp in_stock(session), do: text(session, stock() |> definition("In stock"))

  defp history, do: main() |> region("What happened")
  defp movement(words), do: history() |> row(~r/#{Regex.escape(words)}/)
  # The movements, each as its words, with no row of the heads.
  defp movements(session), do: session |> names(history() |> row(~r/./)) |> tl()

  defp record(summary), do: main() |> region("Record what happened") |> details(summary)
  defp keep(summary), do: main() |> region("Keep the item") |> details(summary)

  test "the pages do not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    for path <- [context.path, context.item_path, context.path <> "/suppliers"] do
      build_conn() |> sign_in(outsider) |> visit(path) |> assert_path("/")
      build_conn() |> visit(path) |> assert_path("/")
    end
  end

  describe "the inventory" do
    test "lists the items with the level and the state of each", context do
      lot!(context)
      Inventory.add_item!(%{name: "Aspen bedding", reorder_level: 2}, context.admin)

      session =
        context.conn
        |> open(context.path)
        |> assert_has(item_row("Meadow hay") |> link("Meadow hay"))
        |> assert_has(item_row("Meadow hay"), text: "Food")
        |> assert_has(item_row("Meadow hay"), text: "10 bag")
        |> assert_has(item_row("Meadow hay"), state: "ok", text: "In stock")
        |> assert_has(item_row("Aspen bedding"), state: "alert", text: "Order more")
        # A member adds no item.
        |> refute_has(button("Add the item"))

      assert shown(session) == ["Aspen bedding", "Meadow hay"]
    end

    test "says so when there is no item", context do
      :ok = Inventory.remove_item(context.hay, context.admin)

      context.conn
      |> open(context.path)
      |> assert_has(items(), text: "The inventory has no item yet.")
    end

    test "gets an item from an administrator, and opens its page", context do
      context.admin_conn
      |> open(context.path)
      |> fill_in("Name", with: "")
      |> send_form("Add the item")
      |> assert_has(main() |> alert(), text: "Name is required")
      |> refute_has(main(), text: "Rescord.Inventory")
      |> fill_in("Name", with: "Guinea pig pellets")
      |> select("Category", option: "Food")
      |> select("Unit that you count it in", option: "kg")
      |> fill_in("Order more when the stock is below", with: "5")
      |> send_form("Add the item")
      |> assert_has(main() |> heading("Guinea pig pellets", level: 1))
      |> assert_has(stock() |> definition("In stock"), text: "0 kg")
      |> assert_has(stock() |> definition("State"), state: "alert", text: "Order more")
      |> assert_has(stock() |> item(~r/wants 5 kg or more/))
    end

    test "gets a medication with its strength, which the page of the item shows", context do
      strength = main() |> region("Stock") |> definition("Strength")
      calculator = main() |> link("Calculate a dose with this strength")

      session =
        context.admin_conn
        |> open(context.path)
        |> fill_in("Name", with: "Meloxicam suspension")
        # The guards of the dose calculator read the number.
        |> fill_in("Amount", with: "1,5")
        |> send_form("Add the item")
        |> assert_has(main() |> alert(), text: "The strength: Write the number with digits")

      # The refused form keeps what the person typed.
      assert value(session, field("Name")) == "Meloxicam suspension"
      assert value(session, field("Amount")) == "1,5"

      session =
        session
        |> select("Category", option: "Medication")
        |> fill_in("Amount", with: "1.5")
        |> select("Unit", option: "mg")
        |> select("In each", option: "mL")
        |> send_form("Add the item")
        |> assert_has(strength, text: "1.5 mg in each mL")

      assert href(session, calculator) =~ "/tools/dose?item="

      # The form of the item has the strength, and an empty field removes it.
      changes = keep("Change the item")
      assert value(session, changes |> field("Amount")) == "1.5"
      assert value(session, changes |> field("Unit of the strength")) == "mg"
      assert value(session, changes |> field("The strength is in each")) == "mL"

      session
      |> within(changes, fn form ->
        form
        |> fill_in("Amount", with: "50")
        |> select("In each", option: "tablet")
        |> send_form("Save the item")
      end)
      |> assert_has(strength, text: "50 mg in each tablet")
      |> within(changes, &(&1 |> fill_in("Amount", with: "0") |> send_form("Save the item")))
      |> assert_has(main() |> alert(), text: "The strength: The strength must be above zero.")
      |> within(changes, &(&1 |> fill_in("Amount", with: "") |> send_form("Save the item")))
      |> refute_has(strength)
      |> refute_has(calculator)
    end

    test "has no strength and no link to the calculator for an item that is no medication",
         context do
      session =
        context.admin_conn
        |> open(context.item_path)
        |> refute_has(stock() |> definition("Strength"))
        |> refute_has(link("Calculate a dose with this strength"))

      assert value(session, keep("Change the item") |> field("Amount")) == nil

      # A form with no strength leaves the item with none.
      session
      |> within(keep("Change the item"), fn form ->
        form |> fill_in("Name", with: "Timothy hay") |> send_form("Save the item")
      end)

      assert {:ok, %{item: %{strength: nil, name: "Timothy hay"}}} =
               Inventory.item_stock(context.hay.id, context.options)
    end

    test "does not take an item from a member who sends the event", context do
      context.conn
      |> open(context.path)
      |> unwrap(&render_submit(&1, "add", %{"item" => %{"name" => "Pellets"}}))
      |> assert_has(main() |> alert(), text: "You cannot do that")

      assert {:ok, [_hay]} = Inventory.stock(context.options)
    end
  end

  describe "the items as a collection (ADR 0088)" do
    setup context do
      lists = context.lists

      # Hay has stock. The bedding has none and wants two. The medication
      # has stock that is past its expiry date.
      lot!(context)

      bedding =
        Inventory.add_item!(
          %{name: "Aspen bedding", category_id: lists.item_category.bedding, reorder_level: 2},
          context.admin
        )

      meloxicam =
        Inventory.add_item!(
          %{name: "Meloxicam", category_id: lists.item_category.medication},
          context.admin
        )

      lot!(context, %{
        item_id: meloxicam.id,
        code: "M-1",
        quantity: 3,
        expires_on: Date.add(context.today, -1)
      })

      {:ok, bedding: bedding, meloxicam: meloxicam}
    end

    test "reads the search, the filters and the sort from the address", context do
      for {parameters, shown} <- [
            {"", ["Aspen bedding", "Meadow hay", "Meloxicam"]},
            {"?search=hay", ["Meadow hay"]},
            {"?category_id=#{context.lists.item_category.bedding}", ["Aspen bedding"]},
            {"?state=attention", ["Aspen bedding", "Meloxicam"]},
            {"?state=short", ["Aspen bedding"]},
            {"?state=expired", ["Meloxicam"]},
            {"?state=expired&search=hay", []},
            # A value that is no choice changes nothing, and makes no fault.
            {"?state=nothing&category_id=x&page=x", ["Aspen bedding", "Meadow hay", "Meloxicam"]},
            {"?sort=-name", ["Meloxicam", "Meadow hay", "Aspen bedding"]}
          ] do
        session = open(context.conn, context.path <> parameters)
        assert shown(session) == shown, "#{parameters} shows #{inspect(shown(session))}"
      end
    end

    test "writes a filter into the address, and says when nothing matches", context do
      session =
        context.conn
        |> open(context.path)
        |> unwrap(fn view ->
          view
          |> element("#items-filter-form")
          |> render_change(%{"filters" => %{"state" => "short"}})

          assert assert_patch(view) =~ "state=short"
          render_async(view)
        end)

      assert shown(session) == ["Aspen bedding"]

      context.conn
      |> open(context.path <> "?state=soon")
      |> assert_has(items(), text: "No item matches the search and the filters.")
      |> refute_has(items(), text: "The inventory has no item yet.")
    end

    test "shows the state of each item of a page, and has pages", context do
      for number <- 10..35 do
        Inventory.add_item!(%{name: "Bowl #{number}"}, context.admin)
      end

      # 29 items: the first page has 25, in the order of the names.
      session =
        context.conn
        |> open(context.path)
        |> assert_has("#items button[title='Next page']")

      assert shown(session) == ["Aspen bedding" | Enum.map(10..33, &"Bowl #{&1}")]

      session = open(context.conn, context.path <> "?page=2")
      assert shown(session) == ["Bowl 34", "Bowl 35", "Meadow hay", "Meloxicam"]

      session
      |> assert_has(item_row("Meadow hay"), text: "10 bag")
      |> assert_has(item_row("Meadow hay"), state: "ok", text: "In stock")
      |> assert_has(item_row("Meloxicam"), state: "alert", text: "past its expiry date")
    end

    test "offers each category as a choice of the filter, and each fault", context do
      session = open(context.conn, context.path)

      for words <- ["Any category", "Food", "Bedding", "Medication"] do
        assert_has(session, "#items-filter-category_id-options label", text: words)
      end

      for {words, value} <- InventoryWords.fault_options() do
        assert_has(session, ~s|#items-filter-state-options input[value="#{value}"] + span|,
          text: words
        )
      end
    end
  end

  describe "the page of an item" do
    test "has its lots with the expiry and the level in each place", context do
      lot = lot!(context, %{expires_on: Date.add(context.today, 10)})

      {:ok, _} =
        Inventory.move_stock(
          %{
            lot_id: lot.id,
            location_id: context.shed.id,
            to_location_id: context.clinic.id,
            quantity: 4
          },
          context.options
        )

      lot!(context, %{code: "A-0", quantity: 1, expires_on: Date.add(context.today, -3)})

      session = open(context.conn, context.item_path)
      assert in_stock(session) == "11 bag"

      session
      |> assert_has(lot_row("Lot B-1"), state: "info", text: "Expires soon")
      |> assert_has(lot_row("Lot B-1") |> item("Feed shed: 6 bag"))
      |> assert_has(lot_row("Lot B-1") |> item("Clinic room: 4 bag"))
      |> assert_has(lot_row("Lot A-0"), state: "alert", text: "Past its expiry date")
      |> assert_has(stock() |> definition("State"),
        state: "alert",
        text: "Has stock past its expiry date"
      )
      |> assert_has(movement("Moved out"))
      |> assert_has(movement("Moved in"), text: "+4")
      |> assert_has(movement("Moved out"), text: "−4")
      |> assert_has(movement("Moved out"), text: to_string(context.member.email))
      # The page shows the words of a kind, and not its atom.
      |> refute_has(history() |> row(~r/\bmoved\b/))

      # The lot that expires first is at the top.
      assert [_heads, "Lot A-0" <> _ | _] = names(session, stock() |> row(~r/./))
    end

    test "names a root user who recorded a movement, to that user", context do
      Inventory.receive_lot!(
        %{item_id: context.hay.id, quantity: 1},
        actor: context.root,
        tenant: context.organisation
      )

      build_conn()
      |> sign_in(context.root)
      |> open(context.item_path)
      |> assert_has(movement("Received"), text: to_string(context.root.email))

      # A member reads that the person is the operator (ADR 0105).
      context.conn
      |> open(context.item_path)
      |> assert_has(movement("Received"), text: "Rescord operator")
    end

    test "says so when the item has no stock, and has no form to take stock", context do
      context.conn
      |> open(context.item_path)
      |> assert_has(stock(), text: "There is no stock of this item.")
      |> assert_has(history(), text: "Nothing happened to the stock of this item yet.")
      |> assert_has(record("Stock came in"))
      |> refute_has(record("Stock was used"))
      |> refute_has(record("Stock moved to another place"))
      |> refute_has(record("I counted the stock"))
    end

    test "goes to the inventory when the item of the address is not there", context do
      for id <- [Ash.UUID.generate(), "not-an-id"] do
        context.conn
        |> visit(context.path <> "/#{id}")
        |> assert_path(context.path)
        |> assert_has(alert(), text: "That item is not in the inventory.")
      end
    end

    test "keeps a lot with nothing left out of the table", context do
      lot = lot!(context)

      {:ok, _} =
        Inventory.use_stock(
          %{lot_id: lot.id, location_id: context.shed.id, quantity: 10},
          context.options
        )

      context.conn
      |> open(context.item_path)
      |> refute_has(stock() |> table(nil))
      |> assert_has(stock() |> details("Lots with nothing left (1)") |> item("Lot B-1"))
    end
  end

  describe "the history on the page of an item (ADR 0084)" do
    setup context do
      old = lot!(context, %{code: "A-0", quantity: 40})
      new = lot!(context, %{code: "B-1", quantity: 5})
      here = %{lot_id: old.id, location_id: context.shed.id, quantity: 1}

      # 27 movements out of the first lot: one thrown out a week ago, and
      # the others used now. With the two that received the lots, 29.
      week_ago = DateTime.add(DateTime.utc_now(), -7, :day)
      Inventory.discard_stock!(Map.put(here, :happened_at, week_ago), context.options)
      for _each <- 1..26, do: Inventory.use_stock!(here, context.options)

      {:ok, old: old, new: new, week_ago: week_ago}
    end

    # The filter of the history is a control of Cinder.
    defp filter_history(session, filters) do
      unwrap(session, fn view ->
        view |> element("#history-filter-form") |> render_change(%{"filters" => filters})
        render_async(view)
      end)
    end

    test "shows a page of 25 movements, the newest first, and the next page", context do
      session = open(context.conn, context.item_path)

      assert [newest | _] = movements(session)
      assert length(movements(session)) == 25
      assert newest =~ "Used"
      refute_has(session, movement("Thrown out"))

      session =
        unwrap(session, fn view ->
          view |> element("#history [phx-click=goto_page][title='Next page']") |> render_click()
          render_async(view)
        end)

      assert length(movements(session)) == 4
      assert_has(session, movement("Thrown out"))
    end

    test "narrows the movements to a kind, to a lot and to dates", context do
      session = context.conn |> open(context.item_path) |> filter_history(%{"kind" => "received"})
      assert length(movements(session)) == 2
      refute_has(session, movement("Used"))

      session = filter_history(session, %{"kind" => "", "lot_id" => context.new.id})
      assert [only] = movements(session)
      assert only =~ "Lot B-1"

      day = context.week_ago |> DateTime.to_date() |> Date.to_iso8601()

      session =
        filter_history(session, %{
          "lot_id" => "",
          "happened_at_from" => day,
          "happened_at_to" => day
        })

      assert [only] = movements(session)
      assert only =~ "Thrown out"

      session
      |> filter_history(%{"kind" => "counted", "happened_at_from" => "", "happened_at_to" => ""})
      |> assert_has(history(), text: "No movement matches the filters.")
    end

    test "says so for an item with no movement", context do
      nothing = Inventory.add_item!(%{name: "Aspen bedding"}, context.admin)

      context.conn
      |> open(context.path <> "/" <> nothing.id)
      |> assert_has(history(), text: "Nothing happened to the stock of this item yet.")
    end

    test "does not put its filters into the address", context do
      context.conn
      |> open(context.item_path)
      |> filter_history(%{"kind" => "received"})
      |> unwrap(fn view ->
        refute_patched(view, context.item_path <> "?kind=received")
        render_async(view)
      end)
    end
  end

  describe "a member on the page of an item" do
    test "records a new lot that came in", context do
      expires = Date.add(context.today, 90)

      context.conn
      |> open(context.item_path)
      |> within(record("Stock came in"), fn form ->
        form
        |> fill_in("Code on the pack of a new lot, if it has one", with: "B-7")
        |> fill_in("Expiry date of a new lot, if it has one", with: Date.to_iso8601(expires))
        |> fill_in("How much came in, in bag", with: "12.5")
        |> select("Where it is now", option: "Feed shed")
        |> send_form("Record the stock")
      end)
      |> assert_has(lot_row("Lot B-7") |> item("Feed shed: 12.5 bag"))
      |> assert_has(movement("Received"), text: "+12.5")

      assert [%{lot: %{expires_on: ^expires}}] = stock!(context).lots
    end

    test "records more of a lot that is there", context do
      lot!(context)

      context.conn
      |> open(context.item_path)
      |> within(record("Stock came in"), fn form ->
        form
        |> select("Lot", option: "Lot B-1")
        |> fill_in("How much came in, in bag", with: "5")
        |> select("Where it is now", option: "Clinic room")
        |> send_form("Record the stock")
      end)

      assert level(context) == "15"
      assert [_one_lot] = stock!(context).lots
    end

    test "records a use, a discard and a move", context do
      lot!(context)
      source = "Lot B-1, Feed shed"

      session =
        context.conn
        |> open(context.item_path)
        |> within(record("Stock was used"), fn form ->
          assert value(form, field("From which lot and place")) == "Lot B-1, Feed shed: 10 bag"

          form
          |> select("From which lot and place", option: source, exact_option: false)
          |> fill_in("How much was used, in bag", with: "2")
          |> send_form("Record the use")
        end)
        |> assert_has(movement("Used"), text: "−2")

      assert level(context) == "8"

      session =
        session
        |> within(record("Stock was thrown out"), fn form ->
          form
          |> select("From which lot and place", option: source, exact_option: false)
          |> fill_in("How much was thrown out, in bag", with: "1")
          |> fill_in("Why", with: "Wet")
          |> send_form("Record the discard")
        end)
        |> assert_has(movement("Thrown out"), text: "Wet")

      session
      |> within(record("Stock moved to another place"), fn form ->
        form
        |> select("From which lot and place", option: source, exact_option: false)
        |> select("To which place", option: "Clinic room")
        |> fill_in("How much moved, in bag", with: "3")
        |> send_form("Record the move")
      end)
      |> assert_has(lot_row("Lot B-1") |> item("Feed shed: 4 bag"))
      |> assert_has(lot_row("Lot B-1") |> item("Clinic room: 3 bag"))

      assert level(context) == "7"
    end

    test "can take more than is there, and the page asks for a count", context do
      lot!(context)
      below_zero = stock() |> item(~r/^Lot B-1, Feed shed: the record has/)

      context.conn
      |> open(context.item_path)
      |> refute_has(below_zero)
      |> within(record("Stock was used"), fn form ->
        form
        |> fill_in("How much was used, in bag", with: "11")
        |> send_form("Record the use")
      end)
      |> assert_has(below_zero)
      |> assert_has(stock() |> definition("State"), state: "alert", text: "Count the stock")
      |> tap(fn _session -> assert level(context) == "-1" end)
      |> within(record("I counted the stock"), fn form ->
        form
        |> select("Lot", option: "Lot B-1")
        |> select("Place", option: "Feed shed")
        |> fill_in("How much is there, in bag", with: "2")
        |> send_form("Record the count")
      end)
      |> refute_has(below_zero)

      assert level(context) == "2"
    end

    test "records a count, and the history says what it found", context do
      lot!(context)

      context.conn
      |> open(context.item_path)
      |> within(record("I counted the stock"), fn form ->
        form
        |> select("Place", option: "Feed shed")
        |> fill_in("How much is there, in bag", with: "7")
        |> send_form("Record the count")
      end)
      |> assert_has(movement("Counted: less than the record"), text: "−3")
      |> assert_has(lot_row("Lot B-1") |> item("Feed shed: 7 bag"))
    end

    test "gives the time that a thing happened, which is not after now", context do
      lot!(context)
      tomorrow = Date.to_iso8601(Date.add(context.today, 1)) <> "T08:00"

      context.conn
      |> open(context.item_path)
      |> within(record("Stock was used"), fn form ->
        form
        |> fill_in("How much was used, in bag", with: "1")
        |> fill_in("When, if not now", with: tomorrow)
        |> send_form("Record the use")
      end)
      |> assert_has(record("Stock was used") |> alert(), text: "The time cannot be after now")

      assert level(context) == "10"
    end

    test "does not take a source that the page did not offer", context do
      lot!(context)
      session = open(context.conn, context.item_path)

      for source <- ["", "x", "#{Ash.UUID.generate()}|", "|#{context.shed.id}"] do
        session
        |> unwrap(&render_submit(&1, "use", %{"use" => %{"source" => source, "quantity" => "1"}}))
        |> assert_has(main() |> alert())
      end

      assert level(context) == "10"
    end

    test "does not move a lot of another item from the page of this item", context do
      pellets = Inventory.add_item!(%{name: "Pellets"}, context.admin)

      other =
        Inventory.receive_lot!(
          %{item_id: pellets.id, quantity: 5, location_id: context.shed.id},
          context.options
        )

      lot!(context)
      session = open(context.conn, context.item_path)
      source = "#{other.id}|#{context.shed.id}"

      for {event, fields} <- [
            {"use", %{"use" => %{"source" => source, "quantity" => "1"}}},
            {"discard", %{"discard" => %{"source" => source, "quantity" => "1"}}},
            {"move", %{"move" => %{"source" => source, "quantity" => "1"}}},
            {"count", %{"count" => %{"lot_id" => other.id, "counted" => "0"}}},
            {"receive", %{"receive" => %{"lot_id" => other.id, "quantity" => "1"}}}
          ] do
        session
        |> unwrap(&render_submit(&1, event, fields))
        |> assert_has(main() |> alert(), text: "Choose a lot of Meadow hay")
      end

      {:ok, %{level: level}} = Inventory.item_stock(pellets.id, context.options)
      assert InventoryWords.plain(level) == "5"
    end

    test "has no form to change the item, to set a level, or to remove the item", context do
      context.conn
      |> open(context.item_path)
      |> refute_has(main() |> details("Change the item"))
      |> refute_has(main() |> details(~r/^Reorder levels in a location/))
      |> refute_has(main() |> details("Remove the item"))
      |> unwrap(&render_submit(&1, "revise", %{"item" => %{"name" => "Hay"}}))
      |> assert_has(main() |> alert(), text: "You cannot do that")
      |> unwrap(&render_click(&1, "remove", %{}))
      |> assert_has(main() |> alert(), text: "You cannot do that")

      assert {:ok, %{item: %{name: "Meadow hay"}}} =
               Inventory.item_stock(context.hay.id, context.options)
    end
  end

  describe "an administrator on the page of an item" do
    test "changes the item, with the form that has its facts", context do
      {:ok, _} = Inventory.revise_item(context.hay, %{reorder_level: "2.5"}, context.admin)
      changes = keep("Change the item")
      reorder_level = "Order more when the stock is below"
      session = open(context.admin_conn, context.item_path)

      assert value(session, changes |> field("Name")) == "Meadow hay"
      assert value(session, changes |> field(reorder_level)) == "2.5"
      assert value(session, changes |> field("Unit that you count it in")) == "bag"

      session
      |> assert_has(stock() |> item(~r/is good to use/))
      |> within(changes, fn form ->
        form
        |> fill_in("Name", with: "Timothy hay")
        |> fill_in(reorder_level, with: "")
        |> send_form("Save the item")
      end)
      |> assert_has(main() |> heading("Timothy hay", level: 1))
      |> refute_has(stock() |> item(~r/is good to use/))

      assert {:ok, %{item: %{reorder_level: nil}}} =
               Inventory.item_stock(context.hay.id, context.options)
    end

    test "gives the item a reorder level in a location, and removes it", context do
      lot!(context)
      levels = keep(~r/^Reorder levels in a location/)

      set_level = fn session, quantity ->
        within(session, levels, fn form ->
          form
          |> select("Location", option: "Clinic room")
          |> fill_in("Bring more to this location when the stock there is below",
            with: quantity
          )
          |> send_form("Save the level")
        end)
      end

      context.admin_conn
      |> open(context.item_path)
      |> set_level.("3")
      |> assert_has(levels |> item(~r/^Clinic room: bring more when/))
      |> assert_has(stock() |> item(~r/^Clinic room has 0 bag that is good to use/))
      |> assert_has(stock() |> definition("State"), state: "alert", text: "Order more")
      |> set_level.("")
      |> refute_has(levels |> item(~r/bring more when/))
      |> refute_has(stock() |> item(~r/is good to use/))
    end

    test "keeps the capitals of the name of a location that starts a line", context do
      ward = Locations.add_location!(%{name: "ICU ward B"}, context.admin)
      lot!(context, %{location_id: ward.id})
      levels = keep(~r/^Reorder levels in a location/)

      context.admin_conn
      |> open(context.item_path)
      |> within(levels, fn form ->
        form
        |> select("Location", option: "ICU ward B")
        |> fill_in("Bring more to this location when the stock there is below",
          with: "20"
        )
        |> send_form("Save the level")
      end)
      |> assert_has(lot_row("Lot B-1") |> item("ICU ward B: 10 bag"))
      |> assert_has(movement("Received"), text: "ICU ward B")
      |> assert_has(levels |> item(~r/^ICU ward B: bring more when/))
      |> assert_has(stock() |> item(~r/^ICU ward B has 10 bag that is good to use/))
    end

    test "removes the item", context do
      context.admin_conn
      |> open(context.item_path)
      |> click(keep("Remove the item") |> button("Remove Meadow hay"))
      |> settle()
      |> assert_path(context.path)
      |> assert_has(status(), text: "Meadow hay is not in the inventory now.")
      |> assert_has(items(), text: "The inventory has no item yet.")
    end
  end

  # The items and the history of an item are collections of temporal
  # resources: a read again with the instant of the first draw would not
  # find what changed after it (ADR 0096, "With Cinder").
  describe "the pages hear what another person changed (ADR 0096)" do
    test "the inventory shows a new item, a new level and a removal", context do
      session =
        context.conn
        |> open(context.path)
        |> assert_has(item_row("Meadow hay"), state: "none", text: "None in stock")

      assert shown(session) == ["Meadow hay"]

      bedding = Inventory.add_item!(%{name: "Aspen bedding"}, context.admin)
      assert session |> render_changes() |> shown() == ["Aspen bedding", "Meadow hay"]

      # A delivery of another member changes the level of the hay.
      lot!(context)

      session
      |> render_changes()
      |> assert_has(item_row("Meadow hay"), text: "10 bag")
      |> assert_has(item_row("Meadow hay"), state: "ok", text: "In stock")

      :ok = Inventory.remove_item(bedding, context.admin)
      assert session |> render_changes() |> shown() == ["Meadow hay"]
    end

    test "the inventory keeps its filter when it reads again", context do
      session =
        context.conn
        |> open(context.path <> "?state=short")
        |> assert_has(items(), text: "No item matches the search and the filters.")

      # The bedding wants two and has none, so it is short. The filter reads
      # the stock as of the new instant too.
      Inventory.add_item!(%{name: "Aspen bedding", reorder_level: 2}, context.admin)
      Inventory.add_item!(%{name: "Wire brush"}, context.admin)

      assert session |> render_changes() |> shown() == ["Aspen bedding"]
    end

    test "the page of an item shows the stock and the history of another member", context do
      session =
        context.conn
        |> open(context.item_path)
        |> assert_has(stock(), text: "There is no stock of this item.")
        |> refute_has(record("Stock was used"))

      lot = lot!(context)
      session = render_changes(session)
      assert in_stock(session) == "10 bag"

      session
      |> assert_has(lot_row("Lot B-1") |> item("Feed shed: 10 bag"))
      |> assert_has(movement("Lot B-1"))
      |> refute_has(history(), text: "Nothing happened to the stock of this item yet.")

      # The forms that take stock out are there now, with the new lot.
      assert value(session, record("Stock was used") |> field("From which lot and place")) ==
               "Lot B-1, Feed shed: 10 bag"

      Inventory.use_stock!(
        %{lot_id: lot.id, location_id: context.shed.id, quantity: 3},
        context.admin
      )

      session = render_changes(session)
      assert in_stock(session) == "7 bag"
      assert_has(session, movement("Used"), text: "−3")
    end

    test "the page of an item leaves its forms alone when it reads again", context do
      tomorrow = Date.to_iso8601(Date.add(context.today, 1)) <> "T08:00"
      came_in = record("Stock came in")

      session =
        context.conn
        |> open(context.item_path)
        |> within(came_in, fn form ->
          form
          |> fill_in("How much came in, in bag", with: "4")
          |> fill_in("Code on the pack of a new lot, if it has one", with: "C-9")
          |> fill_in("When it came in, if not now", with: tomorrow)
          |> send_form("Record the stock")
        end)
        |> assert_has(came_in |> alert(), text: "The time cannot be after now")

      lot!(context)
      session = render_changes(session)
      assert in_stock(session) == "10 bag"

      # The refused form keeps what the person typed, and why it was refused.
      assert value(session, came_in |> field("Code on the pack of a new lot, if it has one")) ==
               "C-9"

      assert_has(session, came_in |> alert(), text: "The time cannot be after now")
    end

    # The page sends the person away by itself, so the test holds the view.
    test "the page of an item goes to the inventory when another person removes it",
         context do
      {:ok, view, _html} = live(context.conn, context.item_path)
      :ok = Inventory.remove_item(context.hay, context.admin)

      {path, flash} = assert_redirect(view)
      assert path == context.path
      assert flash["info"] == "Meadow hay is not in the inventory now."
    end
  end

  describe "the suppliers" do
    test "are a list that a member reads, with no form", context do
      Inventory.add_supplier!(%{name: "Valley Feeds", contact: "07 5550 0100"}, context.admin)

      context.conn
      |> open(context.path <> "/suppliers")
      |> assert_has(main() |> row(~r/^Valley Feeds\b/), text: "07 5550 0100")
      |> refute_has(main() |> details("New supplier"))
      |> refute_has(main() |> row(~r/^Supplier\b/), text: "Actions")
      |> unwrap(&render_submit(&1, "add", %{"supplier" => %{"name" => "X"}}))
      |> assert_has(main() |> alert(), text: "You cannot do that")
    end

    test "are kept by an administrator", context do
      supplier = fn name -> main() |> row(~r/^#{name}\b/) end

      session =
        context.admin_conn
        |> open(context.path <> "/suppliers")
        |> assert_has(main(), text: "There is no supplier yet.")
        |> fill_in("Name", with: "Valley Feeds")
        |> fill_in("How to reach it: a telephone number, an address, a person",
          with: "07 5550 0100"
        )
        |> send_form("Add the supplier")
        |> assert_has(supplier.("Valley Feeds"))

      session
      |> within(supplier.("Valley Feeds"), fn row ->
        row
        |> fill_in("Name of Valley Feeds", with: "Valley Stockfeeds")
        |> send_form("Save the supplier")
      end)
      |> assert_has(supplier.("Valley Stockfeeds"), text: "07 5550 0100")
      |> click(supplier.("Valley Stockfeeds") |> button("Remove Valley Stockfeeds"))
      |> settle()
      |> assert_has(main(), text: "There is no supplier yet.")
    end

    test "are in the form of a new lot", context do
      Inventory.add_supplier!(%{name: "Valley Feeds"}, context.admin)

      context.conn
      |> open(context.item_path)
      |> within(record("Stock came in"), fn form ->
        form
        |> select("Supplier of a new lot", option: "Valley Feeds")
        |> fill_in("How much came in, in bag", with: "1")
        |> send_form("Record the stock")
      end)
      |> assert_has(lot_row("A lot with no code"), text: "From Valley Feeds")
      |> assert_has(lot_row("A lot with no code") |> item("No place in particular: 1 bag"))
    end
  end

  describe "the words of the inventory" do
    test "are there for each kind of movement and each state of an expiry" do
      assert Enum.sort(InventoryWords.movements()) ==
               Enum.sort(Rescord.Inventory.MovementKind.values())

      assert Enum.sort(InventoryWords.expiries()) == [:expired, :later, :none, :soon]

      for state <- InventoryWords.expiries() do
        assert is_binary(InventoryWords.expiry(state))
        assert InventoryWords.expiry_kind(state) in ~w(alert info ok none)
      end
    end

    test "say a quantity with its unit, and a change with its sign" do
      item = %{unit: %{label: "kg"}}

      assert InventoryWords.quantity(Decimal.new("1250.50"), item) == "1,250.5 kg"
      assert InventoryWords.quantity(Decimal.new("3"), %{unit: nil}) == "3"
      assert InventoryWords.plain(Decimal.new("1250.50")) == "1250.5"

      assert InventoryWords.change(Decimal.new("-4")) == "−4"
      assert InventoryWords.change(Decimal.new("2.5")) == "+2.5"
      assert InventoryWords.change(Decimal.new("0.0")) == "0"

      assert InventoryWords.lot(%{code: "B-1"}) == "Lot B-1"
      assert InventoryWords.lot(%{code: nil}) == "A lot with no code"
    end

    test "say what a movement was" do
      movement = fn kind, quantity -> %{kind: kind, quantity: Decimal.new(quantity)} end

      assert InventoryWords.movement(movement.(:received, 5)) == "Received"
      assert InventoryWords.movement(movement.(:used, -5)) == "Used"
      assert InventoryWords.movement(movement.(:discarded, -1)) == "Thrown out"
      assert InventoryWords.movement(movement.(:moved, -1)) == "Moved out"
      assert InventoryWords.movement(movement.(:moved, 1)) == "Moved in"
      assert InventoryWords.movement(movement.(:counted, 0)) == "Counted: the same as the record"
    end

    test "say the states of the stock of an item, the fault first" do
      stock = fn facts ->
        Map.merge(
          %{level: Decimal.new(5), expired: Decimal.new(0), soon: Decimal.new(0), short: []},
          facts
        )
      end

      assert InventoryWords.states(stock.(%{})) == [{"In stock", "ok"}]

      assert InventoryWords.states(stock.(%{level: Decimal.new(0)})) == [
               {"None in stock", "none"}
             ]

      assert InventoryWords.states(
               stock.(%{short: [%{}], expired: Decimal.new(1), soon: Decimal.new(2)})
             ) == [
               {"Order more", "alert"},
               {"Has stock past its expiry date", "alert"},
               {"Has stock that expires soon", "info"}
             ]
    end
  end
end
