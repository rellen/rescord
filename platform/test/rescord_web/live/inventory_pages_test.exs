defmodule RescordWeb.InventoryPagesTest do
  @moduledoc """
  Holds the pages of the inventory: the list of the items, the page of one
  item with its lots and what a member records there, and the suppliers.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
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

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp submit(view, conn, selector, fields) do
    {:ok, view, _html} =
      view |> form(selector, fields) |> render_submit() |> follow_redirect(conn)

    {view, render_async(view)}
  end

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

  test "the pages do not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    for path <- [context.path, context.item_path, context.path <> "/suppliers"] do
      assert {:error, {:redirect, %{to: "/"}}} = build_conn() |> sign_in(outsider) |> live(path)
      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), path)
    end
  end

  describe "the inventory" do
    test "lists the items with the level and the state of each", context do
      lot!(context)
      Inventory.add_item!(%{name: "Aspen bedding", reorder_level: 2}, context.admin)

      {view, _html} = open(context.conn, context.path)

      assert has_element?(view, "#item-#{context.hay.id} a", "Meadow hay")
      assert has_element?(view, "#item-#{context.hay.id} td", "Food")
      assert has_element?(view, "#item-#{context.hay.id} td", "10 bag")
      assert has_element?(view, "#item-#{context.hay.id} [data-state=ok]", "In stock")
      assert has_element?(view, "tbody tr:first-child td", "Aspen bedding")
      assert has_element?(view, "tbody tr:first-child [data-state=alert]", "Order more")
      # A member adds no item.
      refute has_element?(view, "#new-item")
    end

    test "says so when there is no item", context do
      :ok = Inventory.remove_item(context.hay, context.admin)
      {_view, html} = open(context.conn, context.path)
      assert html =~ "The inventory has no item yet."
    end

    test "gets an item from an administrator, and opens its page", context do
      {view, _html} = open(context.admin_conn, context.path)

      html = view |> form("#item", item: %{name: ""}) |> render_submit()
      assert has_element?(view, "main p[role=alert]", "Name is required")
      refute html =~ "Rescord.Inventory"

      {view, html} =
        submit(view, context.admin_conn, "#item",
          item: %{
            name: "Guinea pig pellets",
            category_id: context.lists.item_category.food,
            unit_id: context.lists.unit.kg,
            reorder_level: "5"
          }
        )

      assert html =~ "Guinea pig pellets"
      assert has_element?(view, "dd", "0 kg")
      assert has_element?(view, "[data-state=alert]", "Order more")
      assert has_element?(view, "#short li", "wants 5 kg or more")
    end

    test "does not take an item from a member who sends the event", context do
      {view, _html} = open(context.conn, context.path)

      render_submit(view, "add", %{"item" => %{"name" => "Pellets"}})

      assert has_element?(view, "main p[role=alert]", "You cannot do that")
      assert {:ok, [_hay]} = Inventory.stock(context.options)
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

      old = lot!(context, %{code: "A-0", quantity: 1, expires_on: Date.add(context.today, -3)})

      {view, _html} = open(context.conn, context.item_path)

      assert has_element?(view, "dd", "11 bag")
      assert has_element?(view, "#lot-#{lot.id} td", "Lot B-1")
      assert has_element?(view, "#lot-#{lot.id} [data-state=info]", "Expires soon")
      assert has_element?(view, "#lot-#{lot.id} li", "Feed shed: 6 bag")
      assert has_element?(view, "#lot-#{lot.id} li", "Clinic room: 4 bag")
      assert has_element?(view, "#lot-#{old.id} [data-state=alert]", "Past its expiry date")
      assert has_element?(view, "dd [data-state=alert]", "Has stock past its expiry date")
      # The lot that expires first is at the top.
      assert has_element?(view, "#lots tbody tr:first-child td", "Lot A-0")

      assert has_element?(view, "#history td", "Moved out")
      assert has_element?(view, "#history td", "Moved in")
      assert has_element?(view, "#history td", "−4")
      assert has_element?(view, "#history td", to_string(context.member.email))
      # The page shows the words of a kind, and not its atom.
      refute has_element?(view, "#history td", ~r/^\s*moved\s*$/)
    end

    test "names a root user who recorded a movement, to that user", context do
      Inventory.receive_lot!(
        %{item_id: context.hay.id, quantity: 1},
        actor: context.root,
        tenant: context.organisation
      )

      {view, _html} = open(sign_in(build_conn(), context.root), context.item_path)
      assert has_element?(view, "#history td", to_string(context.root.email))

      # A member reads that the person is no member.
      {view, _html} = open(context.conn, context.item_path)
      assert has_element?(view, "#history td", "A person who is not a member now")
    end

    test "says so when the item has no stock, and has no form to take stock", context do
      {view, html} = open(context.conn, context.item_path)

      assert html =~ "There is no stock of this item."
      assert html =~ "Nothing happened to the stock of this item yet."
      assert has_element?(view, "#receive")
      refute has_element?(view, "#use")
      refute has_element?(view, "#move")
      refute has_element?(view, "#count")
    end

    test "goes to the inventory when the item of the address is not there", context do
      for id <- [Ash.UUID.generate(), "not-an-id"] do
        assert {:error, {:live_redirect, %{to: to}}} =
                 live(context.conn, context.path <> "/#{id}")

        assert to == context.path
      end
    end

    test "keeps a lot with nothing left out of the table", context do
      lot = lot!(context)

      {:ok, _} =
        Inventory.use_stock(
          %{lot_id: lot.id, location_id: context.shed.id, quantity: 10},
          context.options
        )

      {view, _html} = open(context.conn, context.item_path)

      refute has_element?(view, "#lots")
      assert has_element?(view, "#empty-lots summary", "Lots with nothing left (1)")
      assert has_element?(view, "#empty-lots li", "Lot B-1")
    end
  end

  describe "a member on the page of an item" do
    test "records a new lot that came in", context do
      {view, _html} = open(context.conn, context.item_path)
      expires = Date.add(context.today, 90)

      {view, _html} =
        submit(view, context.conn, "#receive-form",
          receive: %{
            code: "B-7",
            expires_on: Date.to_iso8601(expires),
            quantity: "12.5",
            location_id: context.shed.id
          }
        )

      assert has_element?(view, "#lots td", "Lot B-7")
      assert has_element?(view, "#lots li", "Feed shed: 12.5 bag")
      assert has_element?(view, "#history td", "Received")
      assert has_element?(view, "#history td", "+12.5")
      assert [%{lot: %{expires_on: ^expires}}] = stock!(context).lots
    end

    test "records more of a lot that is there", context do
      lot = lot!(context)
      {view, _html} = open(context.conn, context.item_path)

      {_view, _html} =
        submit(view, context.conn, "#receive-form",
          receive: %{lot_id: lot.id, quantity: "5", location_id: context.clinic.id}
        )

      assert level(context) == "15"
      assert [_one_lot] = stock!(context).lots
    end

    test "records a use, a discard and a move", context do
      lot = lot!(context)
      source = "#{lot.id}|#{context.shed.id}"
      {view, _html} = open(context.conn, context.item_path)

      assert has_element?(view, "#use-form option", "Lot B-1, Feed shed: 10 bag")

      {view, _html} =
        submit(view, context.conn, "#use-form", use: %{source: source, quantity: "2"})

      assert has_element?(view, "#history td", "Used")
      assert level(context) == "8"

      {view, _html} =
        submit(view, context.conn, "#discard-form",
          discard: %{source: source, quantity: "1", note: "Wet"}
        )

      assert has_element?(view, "#history td", "Thrown out")
      assert has_element?(view, "#history td", "Wet")

      {view, _html} =
        submit(view, context.conn, "#move-form",
          move: %{source: source, to_location_id: context.clinic.id, quantity: "3"}
        )

      assert has_element?(view, "#lots li", "Feed shed: 4 bag")
      assert has_element?(view, "#lots li", "Clinic room: 3 bag")
      assert level(context) == "7"
    end

    test "is told when a use takes more than is there, and keeps what they typed", context do
      lot = lot!(context)
      {view, _html} = open(context.conn, context.item_path)

      html =
        view
        |> form("#use-form", use: %{source: "#{lot.id}|#{context.shed.id}", quantity: "11"})
        |> render_submit()

      assert has_element?(
               view,
               "#use p[role=alert]",
               "Quantity is more than the 10 there. Count the place when that number is wrong"
             )

      assert html =~ ~s(value="11")
      assert level(context) == "10"
    end

    test "records a count, and the history says what it found", context do
      lot = lot!(context)
      {view, _html} = open(context.conn, context.item_path)

      {view, _html} =
        submit(view, context.conn, "#count-form",
          count: %{lot_id: lot.id, location_id: context.shed.id, counted: "7"}
        )

      assert has_element?(view, "#history td", "Counted: less than the record")
      assert has_element?(view, "#history td", "−3")
      assert has_element?(view, "#lots li", "Feed shed: 7 bag")
    end

    test "gives the time that a thing happened, which is not after now", context do
      lot = lot!(context)
      source = "#{lot.id}|#{context.shed.id}"
      {view, _html} = open(context.conn, context.item_path)

      tomorrow = Date.to_iso8601(Date.add(context.today, 1)) <> "T08:00"

      view
      |> form("#use-form", use: %{source: source, quantity: "1", at: tomorrow})
      |> render_submit()

      assert has_element?(view, "main p[role=alert]", "The time cannot be after now")
      assert level(context) == "10"
    end

    test "does not take a source that the page did not offer", context do
      lot!(context)
      {view, _html} = open(context.conn, context.item_path)

      for source <- ["", "x", "#{Ash.UUID.generate()}|", "|#{context.shed.id}"] do
        render_submit(view, "use", %{"use" => %{"source" => source, "quantity" => "1"}})
        assert has_element?(view, "main p[role=alert]")
      end

      assert level(context) == "10"
    end

    test "has no form to change the item, to set a level, or to remove the item", context do
      {view, _html} = open(context.conn, context.item_path)

      refute has_element?(view, "#edit-item")
      refute has_element?(view, "#reorder")
      refute has_element?(view, "#remove-item")

      render_submit(view, "revise", %{"item" => %{"name" => "Hay"}})
      assert has_element?(view, "main p[role=alert]", "You cannot do that")

      render_click(view, "remove", %{})
      assert has_element?(view, "main p[role=alert]", "You cannot do that")

      assert {:ok, %{item: %{name: "Meadow hay"}}} =
               Inventory.item_stock(context.hay.id, context.options)
    end
  end

  describe "an administrator on the page of an item" do
    test "changes the item, with the form that has its facts", context do
      {:ok, _} = Inventory.revise_item(context.hay, %{reorder_level: "2.5"}, context.admin)
      {view, _html} = open(context.admin_conn, context.item_path)

      assert has_element?(view, "#item_name[value='Meadow hay']")
      assert has_element?(view, "#item_reorder_level[value='2.5']")
      assert has_element?(view, "#item_unit_id option[selected]", "bag")

      {view, html} =
        submit(view, context.admin_conn, "#item-form",
          item: %{name: "Timothy hay", reorder_level: ""}
        )

      assert html =~ "Timothy hay"
      refute has_element?(view, "#short")

      assert {:ok, %{item: %{reorder_level: nil}}} =
               Inventory.item_stock(context.hay.id, context.options)
    end

    test "gives the item a reorder level in a location, and removes it", context do
      lot!(context)
      {view, _html} = open(context.admin_conn, context.item_path)

      {view, _html} =
        submit(view, context.admin_conn, "#reorder-form",
          reorder: %{location_id: context.clinic.id, quantity: "3"}
        )

      assert has_element?(view, "#wanted li", "Clinic room: bring more when")
      assert has_element?(view, "#short li", "Clinic room has 0 bag that is good to use")
      assert has_element?(view, "dd [data-state=alert]", "Order more")

      {view, _html} =
        submit(view, context.admin_conn, "#reorder-form",
          reorder: %{location_id: context.clinic.id, quantity: ""}
        )

      refute has_element?(view, "#wanted")
      refute has_element?(view, "#short")
    end

    test "removes the item", context do
      {view, _html} = open(context.admin_conn, context.item_path)

      {:ok, _view, html} =
        view
        |> element("#remove-item button")
        |> render_click()
        |> follow_redirect(context.admin_conn)

      assert html =~ "Meadow hay is not in the inventory now."
      assert html =~ "The inventory has no item yet."
    end
  end

  describe "the suppliers" do
    test "are a list that a member reads, with no form", context do
      Inventory.add_supplier!(%{name: "Valley Feeds", contact: "07 5550 0100"}, context.admin)

      {view, _html} = open(context.conn, context.path <> "/suppliers")

      assert has_element?(view, "tbody td", "Valley Feeds")
      assert has_element?(view, "tbody td", "07 5550 0100")
      refute has_element?(view, "#new-supplier")
      refute has_element?(view, "th", "Actions")

      render_submit(view, "add", %{"supplier" => %{"name" => "X"}})
      assert has_element?(view, "main p[role=alert]", "You cannot do that")
    end

    test "are kept by an administrator", context do
      path = context.path <> "/suppliers"
      {view, html} = open(context.admin_conn, path)
      assert html =~ "There is no supplier yet."

      {view, _html} =
        submit(view, context.admin_conn, "#supplier",
          supplier: %{name: "Valley Feeds", contact: "07 5550 0100"}
        )

      assert has_element?(view, "tbody td", "Valley Feeds")
      {:ok, [supplier]} = Inventory.suppliers(context.options)

      {view, _html} =
        submit(view, context.admin_conn, "#change-#{supplier.id}",
          change: %{name: "Valley Stockfeeds"}
        )

      assert has_element?(view, "tbody td", "Valley Stockfeeds")
      assert has_element?(view, "tbody td", "07 5550 0100")

      {_view, html} = submit(view, context.admin_conn, "#remove-#{supplier.id}", %{})
      assert html =~ "There is no supplier yet."
    end

    test "are in the form of a new lot", context do
      supplier = Inventory.add_supplier!(%{name: "Valley Feeds"}, context.admin)
      {view, _html} = open(context.conn, context.item_path)

      {view, _html} =
        submit(view, context.conn, "#receive-form",
          receive: %{supplier_id: supplier.id, quantity: "1"}
        )

      assert has_element?(view, "#lots td small", "From Valley Feeds")
      assert has_element?(view, "#lots li", "No place in particular: 1 bag")
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
