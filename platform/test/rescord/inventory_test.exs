defmodule Rescord.InventoryTest do
  @moduledoc """
  Holds the inventory of an organisation (`docs/domain.md`, section 5.8, and
  ADR 0034): an item has lots, the level is the sum of the stock movements,
  a movement out can take the level below zero, which the stock flags until
  a count, a count writes the difference, and the stock says what is past
  its expiry date and what is below a reorder level.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Inventory, Locations}
  alias Rescord.Inventory.{Levels, StockMovement}

  doctest Levels
  doctest Inventory, only: [days_left: 2]

  setup do
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
     hay: hay}
  end

  defp lot!(context, facts \\ %{}) do
    %{item_id: context.hay.id, quantity: 10, location_id: context.shed.id}
    |> Map.merge(facts)
    |> Inventory.receive_lot!(context.options)
  end

  defp stock!(context, item \\ nil) do
    {:ok, stock} = Inventory.item_stock((item || context.hay).id, context.options)
    stock
  end

  defp number(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp places(lot_stock),
    do: Map.new(lot_stock.places, fn {place, level} -> {place, number(level)} end)

  describe "an item" do
    test "has a name, a category and a unit, and an administrator keeps the list", context do
      {:ok, [stock]} = Inventory.stock(context.options)

      assert stock.item.name == "Meadow hay"
      assert to_string(stock.item.category.label) == "Food"
      assert to_string(stock.item.unit.label) == "bag"
      assert number(stock.level) == "0"
      assert stock.lots == []

      assert {:error, %Ash.Error.Forbidden{}} =
               Inventory.add_item(%{name: "Pellets"}, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Inventory.revise_item(context.hay, %{name: "Hay"}, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Inventory.remove_item(context.hay, context.options)

      assert {:ok, %{name: "Timothy hay"}} =
               Inventory.revise_item(context.hay, %{name: "Timothy hay"}, context.admin)

      assert {:error, %Ash.Error.Invalid{}} = Inventory.add_item(%{}, context.admin)
    end

    test "can have the strength of a medication, a mass in each mL or in each tablet", context do
      {:ok, strength} = Rescord.Units.Quantity.parse("1.5 mg/mL")

      meloxicam =
        Inventory.add_item!(%{name: "Meloxicam suspension", strength: strength}, context.admin)

      {:ok, %{item: read}} = Inventory.item_stock(meloxicam.id, context.options)
      assert to_string(read.strength) == "1.5 mg/mL"

      # A text and a map are read as a form sends them.
      assert {:ok, %{strength: tablets}} =
               Inventory.revise_item(meloxicam, %{strength: "50 mg/tablet"}, context.admin)

      assert to_string(tablets.unit) == "mg/tablet"

      # The history has the strength of each time.
      {:ok, history} = meloxicam.id |> Inventory.query_to_history(context.options) |> Ash.read()
      assert is_list(history)

      assert {:ok, %{strength: nil}} =
               Inventory.revise_item(meloxicam, %{strength: nil}, context.admin)

      # A strength is no dose rate, no plain mass, and above zero.
      for wrong <- ["5 mg/kg", "5 mg", "1 mL", "0 mg/mL", "-1 mg/mL", "5 bags/mL", "five"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Inventory.revise_item(meloxicam, %{strength: wrong}, context.admin),
               wrong
      end

      # An item with no strength is as before.
      assert context.hay.strength == nil
    end

    test "is in the order of the names, and is not there after an administrator removes it",
         context do
      Inventory.add_item!(%{name: "Aspen bedding"}, context.admin)

      {:ok, stock} = Inventory.stock(context.options)
      assert Enum.map(stock, & &1.item.name) == ["Aspen bedding", "Meadow hay"]

      assert :ok = Inventory.remove_item(context.hay, context.admin)

      {:ok, stock} = Inventory.stock(context.options)
      assert Enum.map(stock, & &1.item.name) == ["Aspen bedding"]
      assert {:ok, nil} = Inventory.item_stock(context.hay.id, context.options)
    end
  end

  describe "a supplier" do
    test "is in the list of an administrator, and a lot names it", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Inventory.add_supplier(%{name: "Valley Feeds"}, context.options)

      supplier =
        Inventory.add_supplier!(%{name: "Valley Feeds", contact: "07 5550 0100"}, context.admin)

      lot!(context, %{supplier_id: supplier.id})

      assert [%{lot: %{supplier: %{name: "Valley Feeds"}}}] = stock!(context).lots
      assert {:ok, [%{contact: "07 5550 0100"}]} = Inventory.suppliers(context.options)

      assert {:ok, %{name: "Valley Stockfeeds"}} =
               Inventory.revise_supplier(supplier, %{name: "Valley Stockfeeds"}, context.admin)

      assert :ok = Inventory.remove_supplier(supplier, context.admin)
      assert {:ok, []} = Inventory.suppliers(context.options)
    end
  end

  describe "a lot" do
    test "comes with its first stock, in a place, and says who recorded it", context do
      lot = lot!(context, %{code: "B-4471", expires_on: Date.add(context.today, 200)})

      stock = stock!(context)
      assert number(stock.level) == "10"
      assert [%{lot: %{id: id, code: "B-4471"}, expiry: :later} = lot_stock] = stock.lots
      assert id == lot.id
      assert places(lot_stock) == %{context.shed.id => "10"}

      {:ok, [movement]} =
        context.hay.id |> Inventory.query_to_history(context.options) |> Ash.read()

      assert movement.kind == :received
      assert movement.author_id == context.member.id
      assert movement.lot.code == "B-4471"
    end

    test "needs a quantity that is more than zero, and is not there when the stock is refused",
         context do
      for quantity <- [0, -1] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Inventory.receive_lot(
                   %{item_id: context.hay.id, quantity: quantity},
                   context.options
                 )

        assert Exception.message(error) =~ "must be more than zero"
      end

      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.receive_lot(%{item_id: context.hay.id}, context.options)

      assert stock!(context).lots == []
    end

    test "can be in no place in particular, and with a part of a unit", context do
      lot!(context, %{location_id: nil, quantity: "2.5"})

      assert [lot_stock] = stock!(context).lots
      assert places(lot_stock) == %{nil => "2.5"}
    end

    test "that expires first is at the top, and a lot with no date is the last", context do
      lot!(context, %{code: "no date"})
      lot!(context, %{code: "later", expires_on: Date.add(context.today, 90)})
      lot!(context, %{code: "sooner", expires_on: Date.add(context.today, 40)})

      assert Enum.map(stock!(context).lots, & &1.lot.code) == ["sooner", "later", "no date"]
    end

    test "has facts that a member corrects", context do
      lot = lot!(context)

      assert {:ok, %{code: "B-1", expires_on: expires_on}} =
               Inventory.revise_lot(
                 lot,
                 %{code: "B-1", expires_on: Date.add(context.today, 5)},
                 context.options
               )

      assert expires_on == Date.add(context.today, 5)
    end
  end

  describe "the level" do
    test "is the sum of the movements of a lot in each place", context do
      lot = lot!(context)
      here = %{lot_id: lot.id, location_id: context.shed.id}

      {:ok, _} = Inventory.receive_stock(Map.put(here, :quantity, 5), context.options)
      {:ok, used} = Inventory.use_stock(Map.put(here, :quantity, 4), context.options)
      {:ok, _} = Inventory.discard_stock(Map.put(here, :quantity, "0.5"), context.options)

      assert number(used.quantity) == "-4"
      assert used.kind == :used

      stock = stock!(context)
      assert number(stock.level) == "10.5"
      assert places(hd(stock.lots)) == %{context.shed.id => "10.5"}

      {:ok, history} = context.hay.id |> Inventory.query_to_history(context.options) |> Ash.read()
      assert Enum.map(history, & &1.kind) == [:discarded, :used, :received, :received]
    end

    test "can go below zero, and the stock asks for a count until one", context do
      lot = lot!(context)

      for action <- [&Inventory.use_stock/2, &Inventory.discard_stock/2] do
        assert {:ok, _movement} =
                 action.(
                   %{lot_id: lot.id, location_id: context.shed.id, quantity: 6},
                   context.options
                 )
      end

      # A use from a place with no stock also goes below zero there.
      assert {:ok, _movement} =
               Inventory.use_stock(
                 %{lot_id: lot.id, location_id: context.clinic.id, quantity: 1},
                 context.options
               )

      stock = stock!(context)
      assert number(stock.level) == "-3"

      assert stock.below_zero
             |> Enum.map(fn {%{id: id}, place, level} -> {id, place, number(level)} end)
             |> Enum.sort() ==
               Enum.sort([{lot.id, context.shed.id, "-2"}, {lot.id, context.clinic.id, "-1"}])

      # A count puts each place right, and the warning goes.
      for place <- [context.shed.id, context.clinic.id] do
        assert {:ok, _count} =
                 Inventory.count_stock(
                   %{lot_id: lot.id, location_id: place, counted: 0},
                   context.options
                 )
      end

      stock = stock!(context)
      assert number(stock.level) == "0"
      assert stock.below_zero == []
      assert [%{places: []}] = stock.lots
    end

    test "takes a quantity that is more than zero", context do
      lot = lot!(context)

      for action <- [
            &Inventory.receive_stock/2,
            &Inventory.use_stock/2,
            &Inventory.discard_stock/2
          ],
          quantity <- [0, -3] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 action.(
                   %{lot_id: lot.id, location_id: context.shed.id, quantity: quantity},
                   context.options
                 )

        assert Exception.message(error) =~ "must be more than zero"
      end

      assert number(stock!(context).level) == "10"
    end

    test "is not for a lot that is not there", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Inventory.receive_stock(
                 %{lot_id: Ash.UUID.generate(), quantity: 1},
                 context.options
               )

      assert Exception.message(error) =~ "is not a lot of this organisation"
    end
  end

  describe "a count" do
    test "writes the difference from the level, up or down", context do
      lot = lot!(context)
      here = %{lot_id: lot.id, location_id: context.shed.id}

      {:ok, down} = Inventory.count_stock(Map.put(here, :counted, 7), context.options)
      assert down.kind == :counted
      assert number(down.quantity) == "-3"
      assert number(stock!(context).level) == "7"

      {:ok, up} = Inventory.count_stock(Map.put(here, :counted, "8.5"), context.options)
      assert number(up.quantity) == "1.5"
      assert number(stock!(context).level) == "8.5"

      # A count that is the level records that a member looked.
      {:ok, same} = Inventory.count_stock(Map.put(here, :counted, "8.5"), context.options)
      assert number(same.quantity) == "0"
    end

    test "can find stock in a place that had none, and is not less than zero", context do
      lot = lot!(context)

      {:ok, _} =
        Inventory.count_stock(
          %{lot_id: lot.id, location_id: context.clinic.id, counted: 2},
          context.options
        )

      assert places(hd(stock!(context).lots)) ==
               %{context.shed.id => "10", context.clinic.id => "2"}

      assert {:error, %Ash.Error.Invalid{} = error} =
               Inventory.count_stock(
                 %{lot_id: lot.id, location_id: context.shed.id, counted: -1},
                 context.options
               )

      assert Exception.message(error) =~ "cannot be less than zero"
    end
  end

  describe "a move" do
    test "takes a quantity out of one place and into another, in two movements", context do
      lot = lot!(context)

      assert {:ok, out} =
               Inventory.move_stock(
                 %{
                   lot_id: lot.id,
                   location_id: context.shed.id,
                   to_location_id: context.clinic.id,
                   quantity: 4,
                   note: "For the week"
                 },
                 context.options
               )

      assert number(out.quantity) == "-4"

      stock = stock!(context)
      assert number(stock.level) == "10"
      assert places(hd(stock.lots)) == %{context.shed.id => "6", context.clinic.id => "4"}

      {:ok, history} = context.hay.id |> Inventory.query_to_history(context.options) |> Ash.read()
      moved = Enum.filter(history, &(&1.kind == :moved))

      assert moved |> Enum.map(&{&1.location_id, number(&1.quantity)}) |> Enum.sort() ==
               Enum.sort([{context.shed.id, "-4"}, {context.clinic.id, "4"}])

      assert Enum.all?(moved, &(&1.author_id == context.member.id and &1.note == "For the week"))
      assert [_one] = moved |> Enum.map(& &1.happened_at) |> Enum.uniq()
    end

    test "is refused for the same place, and writes nothing", context do
      lot = lot!(context)
      move = %{lot_id: lot.id, location_id: context.shed.id, quantity: 4}

      assert {:error, %Ash.Error.Invalid{} = error} =
               Inventory.move_stock(
                 Map.put(move, :to_location_id, context.shed.id),
                 context.options
               )

      assert Exception.message(error) =~ "is the place that the stock is in"

      {:ok, history} = context.hay.id |> Inventory.query_to_history(context.options) |> Ash.read()
      assert Enum.map(history, & &1.kind) == [:received]
    end

    test "can be to no place in particular", context do
      lot = lot!(context)

      assert {:ok, _} =
               Inventory.move_stock(
                 %{
                   lot_id: lot.id,
                   location_id: context.shed.id,
                   to_location_id: nil,
                   quantity: 1
                 },
                 context.options
               )

      assert places(hd(stock!(context).lots)) == %{context.shed.id => "9", nil => "1"}
    end
  end

  describe "the time of a movement" do
    test "is the time that the member gives, and never after now", context do
      lot = lot!(context)
      here = %{lot_id: lot.id, location_id: context.shed.id, quantity: 1}
      yesterday = DateTime.add(DateTime.utc_now(), -1, :day)

      {:ok, used} = Inventory.use_stock(Map.put(here, :happened_at, yesterday), context.options)
      assert DateTime.compare(used.happened_at, yesterday) == :eq

      assert {:error, %Ash.Error.Invalid{} = error} =
               Inventory.use_stock(
                 Map.put(here, :happened_at, DateTime.add(DateTime.utc_now(), 1, :hour)),
                 context.options
               )

      assert Exception.message(error) =~ "cannot be after now"

      # The history is in the order of the times that the things happened.
      {:ok, history} = context.hay.id |> Inventory.query_to_history(context.options) |> Ash.read()
      assert Enum.map(history, & &1.kind) == [:received, :used]
    end
  end

  describe "the expiry date of a lot" do
    test "says that the lot is expired, expires soon, or expires later", context do
      today = context.today

      assert Inventory.expiry(%{expires_on: nil}, today) == :none
      assert Inventory.expiry(%{expires_on: Date.add(today, -1)}, today) == :expired
      # A lot is good on its expiry date.
      assert Inventory.expiry(%{expires_on: today}, today) == :soon
      assert Inventory.expiry(%{expires_on: Date.add(today, 30)}, today) == :soon
      assert Inventory.expiry(%{expires_on: Date.add(today, 31)}, today) == :later
    end

    test "gives the stock its part that is expired, and its part that expires soon", context do
      lot!(context, %{quantity: 3, expires_on: Date.add(context.today, -2)})
      lot!(context, %{quantity: 4, expires_on: Date.add(context.today, 10)})
      lot!(context, %{quantity: 5})

      stock = stock!(context)
      assert number(stock.level) == "12"
      assert number(stock.expired) == "3"
      assert number(stock.soon) == "4"
      assert Enum.map(stock.lots, & &1.expiry) == [:expired, :soon, :none]
    end

    test "expires soon in the days that the category of the item gives", context do
      lot!(context, %{quantity: 4, expires_on: Date.add(context.today, 45)})
      assert [:later] = Enum.map(stock!(context).lots, & &1.expiry)

      # A member does not change the days.
      assert {:error, %Ash.Error.Forbidden{}} =
               Rescord.Lists.set_soon_days(context.lists.item_category.food, 60, context.options)

      {:ok, food} =
        Rescord.Lists.set_soon_days(context.lists.item_category.food, 60, context.admin)

      assert food.soon_days == 60

      stock = stock!(context)
      assert [:soon] = Enum.map(stock.lots, & &1.expiry)
      assert number(stock.soon) == "4"

      # Zero days: a lot expires soon on its date alone.
      {:ok, _food} =
        Rescord.Lists.set_soon_days(context.lists.item_category.food, 0, context.admin)

      assert [:later] = Enum.map(stock!(context).lots, & &1.expiry)
      assert Inventory.expiry(%{expires_on: context.today}, context.today, 0) == :soon

      # No number: 30 days again.
      {:ok, food} =
        Rescord.Lists.set_soon_days(context.lists.item_category.food, nil, context.admin)

      assert food.soon_days == nil
      assert Inventory.soon_days(%{category: food}) == 30

      assert {:error, %Ash.Error.Invalid{}} =
               Rescord.Lists.set_soon_days(context.lists.item_category.food, -1, context.admin)
    end

    test "is on the calendar of the organisation", context do
      # These two zones are 25 hours apart, so they never have the same date,
      # and one of them is not on the date of UTC.
      for zone <- ["Pacific/Kiritimati", "Pacific/Pago_Pago"] do
        far = organisation!(context.root, "Far", zone)
        options = [actor: context.root, tenant: far]
        item = Inventory.add_item!(%{name: "Pellets"}, options)
        today = Accounts.today(far)

        for expires_on <- [today, Date.add(today, -1)] do
          Inventory.receive_lot!(
            %{item_id: item.id, quantity: 1, expires_on: expires_on},
            options
          )
        end

        {:ok, stock} = Inventory.item_stock(item.id, options)
        assert Enum.map(stock.lots, & &1.expiry) == [:expired, :soon]
      end
    end
  end

  describe "a reorder level" do
    test "of the whole organisation says when the stock is below it", context do
      {:ok, _} = Inventory.revise_item(context.hay, %{reorder_level: 5}, context.admin)
      assert [%{location_id: nil, wanted: wanted, level: level}] = stock!(context).short
      assert {number(wanted), number(level)} == {"5", "0"}

      lot = lot!(context, %{quantity: 5})
      # The stock is at the level, and not below it.
      assert stock!(context).short == []

      {:ok, _} =
        Inventory.use_stock(
          %{lot_id: lot.id, location_id: context.shed.id, quantity: 1},
          context.options
        )

      assert [%{location_id: nil, level: level}] = stock!(context).short
      assert number(level) == "4"
    end

    test "does not count the stock that is past its expiry date", context do
      {:ok, _} = Inventory.revise_item(context.hay, %{reorder_level: 5}, context.admin)
      lot!(context, %{quantity: 20, expires_on: Date.add(context.today, -1)})
      lot!(context, %{quantity: 2})

      assert [%{location_id: nil, level: level}] = stock!(context).short
      assert number(level) == "2"
    end

    test "of one location says when the stock there is below it", context do
      clinic = context.clinic.id
      lot = lot!(context)

      assert {:ok, %{quantity: _}} =
               Inventory.set_reorder_level(context.hay.id, clinic, 3, context.admin)

      assert [%{location_id: ^clinic, level: level}] = stock!(context).short
      assert number(level) == "0"

      {:ok, _} =
        Inventory.move_stock(
          %{lot_id: lot.id, location_id: context.shed.id, to_location_id: clinic, quantity: 3},
          context.options
        )

      assert stock!(context).short == []

      # A second level for the same place changes the first.
      assert {:ok, _} = Inventory.set_reorder_level(context.hay.id, clinic, 4, context.admin)
      assert {:ok, [%{quantity: quantity}]} = Inventory.reorder_levels(context.options)
      assert number(quantity) == "4"
      assert [%{location_id: ^clinic}] = stock!(context).short

      # No quantity removes the level, and the place can get one again.
      assert {:ok, nil} = Inventory.set_reorder_level(context.hay.id, clinic, nil, context.admin)
      assert {:ok, []} = Inventory.reorder_levels(context.options)
      assert stock!(context).short == []
      assert {:ok, nil} = Inventory.set_reorder_level(context.hay.id, clinic, nil, context.admin)
      assert {:ok, %{}} = Inventory.set_reorder_level(context.hay.id, clinic, 1, context.admin)
    end

    test "is for an administrator to set, and is more than zero", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Inventory.set_reorder_level(context.hay.id, context.clinic.id, 3, context.options)

      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.set_reorder_level(context.hay.id, context.clinic.id, 0, context.admin)

      assert {:error, %Ash.Error.Invalid{}} =
               Inventory.revise_item(context.hay, %{reorder_level: -1}, context.admin)
    end
  end

  describe "the stock of the items of a read (ADR 0088)" do
    setup context do
      # Hay has stock, a part of it past its expiry date. The bedding has
      # none and wants two. The bowls have no lot.
      lot!(context)
      lot!(context, %{code: "B-0", quantity: 4, expires_on: Date.add(context.today, -1)})

      bedding = Inventory.add_item!(%{name: "Aspen bedding", reorder_level: 2}, context.admin)
      bowls = Inventory.add_item!(%{name: "Bowls"}, context.admin)

      {:ok, bedding: bedding, bowls: bowls}
    end

    # What a page shows of the stock of an item.
    defp shown(stock) do
      %{
        name: stock.item.name,
        level: number(stock.level),
        expired: number(stock.expired),
        faults: Inventory.faults(stock),
        lots: Enum.map(stock.lots, &{&1.lot.code, number(&1.level), &1.expiry}),
        short: Enum.map(stock.short, &{&1.location_id, number(&1.wanted), number(&1.level)})
      }
    end

    test "is a calculation of an item, the same as the stock of the organisation", context do
      {:ok, all} = Inventory.stock(context.options)
      {:ok, items} = Inventory.items([query: [load: [:stock]]] ++ context.options)

      assert Enum.map(all, &shown/1) ==
               items |> Enum.sort_by(& &1.name) |> Enum.map(&shown(&1.stock))

      hay = Enum.find(items, &(&1.id == context.hay.id))
      assert number(hay.stock.level) == "14"
      assert Inventory.faults(hay.stock) == [:expired]
      # The stock has the item with its category and its unit.
      assert to_string(hay.stock.item.unit.label) == "bag"
    end

    test "reads the lots and the movements of the items that it is asked for", context do
      {:ok, [bedding]} =
        Inventory.items(
          [query: [filter: [id: context.bedding.id], load: [:stock]]] ++ context.options
        )

      assert %{level: "0", lots: [], faults: [:short]} = shown(bedding.stock)

      # The stock of some items, in the order that they come in.
      load = [load: [category: [:label], unit: [:label]]] ++ context.options
      items = for id <- [context.bowls.id, context.hay.id], do: Inventory.item!(id, load)

      {:ok, [bowls, hay]} = Inventory.stock_of(items, context.options)

      assert {bowls.item.name, hay.item.name} == {"Bowls", "Meadow hay"}
      assert number(hay.level) == "14"
      assert {:ok, []} = Inventory.stock_of([], context.options)
    end

    test "is nothing for a person who can read no stock", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      for actor <- [outsider, nil] do
        options = [actor: actor, tenant: context.organisation]
        assert {:ok, []} = Inventory.items([query: [load: [:stock]]] ++ options)

        # With an item in hand, the calculation reads as the actor: no lot.
        assert {:ok, %{stock: stock}} = Ash.load(context.hay, :stock, options)
        assert %{level: "0", lots: []} = shown(stock)
      end
    end

    test "narrows a query to the items with a fault", context do
      names = fn fault, options ->
        Rescord.Inventory.Item
        |> Ash.Query.for_read(:read, %{}, options)
        |> Inventory.with_fault(fault, options)
        |> Ash.read!()
        |> Enum.map(& &1.name)
        |> Enum.sort()
      end

      assert names.(:any, context.options) == ["Aspen bedding", "Meadow hay"]
      assert names.(:short, context.options) == ["Aspen bedding"]
      assert names.(:expired, context.options) == ["Meadow hay"]
      assert names.(:soon, context.options) == []
      assert names.(:below_zero, context.options) == []

      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)
      assert names.(:any, actor: outsider, tenant: context.organisation) == []
    end
  end

  describe "who can work with the inventory" do
    test "each member and a root user, and not a user of another organisation or nobody",
         context do
      lot = lot!(context)
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      assert {:ok, [_]} = Inventory.stock(actor: context.root, tenant: context.organisation)

      for actor <- [outsider, nil] do
        options = [actor: actor, tenant: context.organisation]
        here = %{lot_id: lot.id, location_id: context.shed.id}

        assert {:ok, []} = Inventory.stock(options)
        assert {:ok, nil} = Inventory.item_stock(context.hay.id, options)
        assert {:ok, []} = context.hay.id |> Inventory.query_to_history(options) |> Ash.read()
        assert {:ok, []} = Inventory.suppliers(options)

        assert {:error, %Ash.Error.Forbidden{}} = Inventory.add_item(%{name: "X"}, options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Inventory.receive_lot(%{item_id: context.hay.id, quantity: 1}, options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Inventory.receive_stock(Map.put(here, :quantity, 1), options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Inventory.use_stock(Map.put(here, :quantity, 1), options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Inventory.count_stock(Map.put(here, :counted, 0), options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Inventory.move_stock(
                   Map.merge(here, %{quantity: 1, to_location_id: context.clinic.id}),
                   options
                 )
      end

      assert number(stock!(context).level) == "10"
    end

    test "no member runs the second half of a move, or gives a movement its sign", context do
      lot = lot!(context)

      assert {:error, %Ash.Error.Forbidden{}} =
               StockMovement
               |> Ash.Changeset.for_create(
                 :move_in,
                 %{lot_id: lot.id, location_id: context.clinic.id, quantity: 5},
                 context.options
               )
               |> Ash.create()

      for input <- [%{quantity: 1, kind: :received}, %{quantity: 1, author_id: context.root.id}] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Inventory.use_stock(
                   Map.merge(%{lot_id: lot.id, location_id: context.shed.id}, input),
                   context.options
                 )
      end

      refute Inventory.role_can?(:administrator, :movement, :move_in)
      assert Inventory.role_can?(:member, :movement, :use)
      assert Inventory.role_can?(:member, :lot, :receive)
      refute Inventory.role_can?(:member, :item, :add)
      assert Inventory.role_can?(:administrator, :item, :add)
      refute Inventory.role_can?(:member, :reorder_level, :set)
    end
  end

  describe "the stock over time and the days left (ADR 0123)" do
    test "has the level at the end of each day, and the use of the last 30 days", context do
      now = DateTime.utc_now()
      lot = lot!(context, %{happened_at: DateTime.add(now, -40, :day)})
      here = %{lot_id: lot.id, location_id: context.shed.id}

      {:ok, _} =
        Inventory.use_stock(
          Map.merge(here, %{quantity: 2, happened_at: DateTime.add(now, -35, :day)}),
          context.options
        )

      {:ok, _} =
        Inventory.use_stock(Map.merge(here, %{quantity: 3, happened_at: now}), context.options)

      {:ok, _} =
        Inventory.discard_stock(Map.put(here, :quantity, "1.5"), context.options)

      today = context.today

      {:ok, trend} =
        Inventory.levels_by_day(context.hay.id, Date.add(today, -2), today, context.options)

      assert Enum.map(trend.levels, fn {date, level} -> {date, number(level)} end) == [
               {Date.add(today, -2), "8"},
               {Date.add(today, -1), "8"},
               {today, "3.5"}
             ]

      assert number(trend.used) == "4.5"
      assert {:ok, %{} = used} = Inventory.use_by_item(today, context.options)
      assert number(used[context.hay.id]) == "4.5"
      assert Inventory.days_left(Decimal.new("3.5"), trend.used) == 23
    end

    test "read nothing for a user of another organisation", context do
      lot!(context)
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      assert {:ok, used} = Inventory.use_by_item(context.today, actor: outsider, tenant: other)
      assert used == %{}
    end
  end
end
