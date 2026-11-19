defmodule Rescord.Inventory do
  @moduledoc """
  The inventory of an organisation: its supplies (`docs/domain.md`,
  section 5.8, and ADR 0034).

  An item has lots, and a lot has stock movements. Rescord stores no level:
  `stock/1` calculates the level of each item, of each lot, and of each lot
  in each place, from the movements. It also says which stock is past its
  expiry date, which expires soon, and which item is below a reorder level.

  A member records what happens with `receive_lot/2`, `receive_stock/2`,
  `use_stock/2`, `move_stock/2`, `discard_stock/2` and `count_stock/2`.

  Each resource here is temporal (ADR 0012), so a change keeps the record
  as it was.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.Inventory.{Item, Levels, Lot, ReorderLevel, StockMovement, Supplier}

  boundary do
    deps [Rescord, Rescord.Accounts, Rescord.Lists, Rescord.Locations]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Inventory.Item do
      define :items, action: :read
      define :item, action: :read, get_by: [:id], not_found_error?: false
      define :add_item, action: :add
      define :revise_item, action: :revise
      define :remove_item, action: :remove
    end

    resource Rescord.Inventory.Supplier do
      define :suppliers, action: :read
      define :add_supplier, action: :add
      define :revise_supplier, action: :revise
      define :remove_supplier, action: :remove
    end

    resource Rescord.Inventory.Lot do
      define :lots, action: :read
      define :lot, action: :read, get_by: [:id], not_found_error?: false
      define :receive_lot, action: :receive
      define :revise_lot, action: :revise
    end

    resource Rescord.Inventory.StockMovement do
      define :receive_stock, action: :receive
      define :use_stock, action: :use
      define :discard_stock, action: :discard
      define :count_stock, action: :count
      define :move_stock, action: :move
    end

    resource Rescord.Inventory.ReorderLevel do
      define :reorder_levels, action: :read
    end
  end

  # A lot expires soon in this number of days before its expiry date, when
  # its category gives no number of its own.
  @soon_days 30

  @typedoc """
  The stock of one item:

    * `item` - the item, with its category and its unit;
    * `level` - the quantity in all its lots;
    * `expired` - the part of the level that is past its expiry date;
    * `soon` - the part of the level that expires soon, in the days that the
      category of the item gives, or 30;
    * `below_zero` - each place of a lot whose level is below zero, as
      `{lot, place, level}`: a member used more than the record had, and a
      count puts it right;
    * `lots` - each lot with its level, its places and its expiry, the lot
      that expires first at the top;
    * `short` - each reorder level that the stock is below: the place (`nil`
      is the whole organisation), the quantity that the organisation wants,
      and the level there. Stock that is past its expiry date does not
      count.
  """
  @type stock :: %{
          item: Ash.Resource.record(),
          level: Decimal.t(),
          expired: Decimal.t(),
          soon: Decimal.t(),
          below_zero: [{Ash.Resource.record(), String.t() | nil, Decimal.t()}],
          lots: [lot_stock],
          short: [%{location_id: String.t() | nil, wanted: Decimal.t(), level: Decimal.t()}]
        }

  @typedoc "The stock of one lot: its level, and each place with a level that is not zero."
  @type lot_stock :: %{
          lot: Ash.Resource.record(),
          level: Decimal.t(),
          places: [{String.t() | nil, Decimal.t()}],
          expiry: :expired | :soon | :later | :none
        }

  @doc "The stock of each item of the organisation, in the order of the names."
  @spec stock(keyword) :: {:ok, [stock]} | {:error, term}
  def stock(opts \\ []) do
    with {:ok, items} <- read_items(Item, opts),
         {:ok, lots} <- Lot |> Ash.Query.load(:supplier) |> Ash.read(opts),
         {:ok, movements} <- read_movements(StockMovement, opts),
         {:ok, wanted} <- Ash.read(ReorderLevel, opts) do
      {:ok, build(items, lots, movements, wanted, opts)}
    end
  end

  @doc "The stock of one item, or `nil` when the actor can read no such item."
  @spec item_stock(String.t(), keyword) :: {:ok, stock | nil} | {:error, term}
  def item_stock(item_id, opts \\ []) do
    with {:ok, [item]} <- read_items(Ash.Query.filter(Item, id == ^item_id), opts),
         {:ok, lots} <-
           Lot
           |> Ash.Query.filter(item_id == ^item_id)
           |> Ash.Query.load(:supplier)
           |> Ash.read(opts),
         lot_ids = Enum.map(lots, & &1.id),
         {:ok, movements} <-
           read_movements(Ash.Query.filter(StockMovement, lot_id in ^lot_ids), opts),
         {:ok, wanted} <- ReorderLevel |> Ash.Query.filter(item_id == ^item_id) |> Ash.read(opts) do
      {:ok, hd(build([item], lots, movements, wanted, opts))}
    else
      {:ok, []} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  defp read_items(query, opts) do
    query
    |> Ash.Query.sort(name: :asc, id: :asc)
    |> Ash.Query.load(category: [:label], unit: [:label])
    |> Ash.read(opts)
  end

  defp read_movements(query, opts) do
    query |> Ash.Query.select([:lot_id, :location_id, :quantity]) |> Ash.read(opts)
  end

  defp build(items, lots, movements, wanted, opts) do
    places_of = movements |> Levels.by_place() |> Levels.by_lot()
    today = Rescord.Accounts.today(opts[:tenant])
    lots_of = Enum.group_by(lots, & &1.item_id)
    wanted_of = Enum.group_by(wanted, & &1.item_id)

    for item <- items do
      lots =
        lots_of
        |> Map.get(item.id, [])
        |> Enum.map(fn lot ->
          places = Map.get(places_of, lot.id, [])

          %{
            lot: lot,
            level: places |> Enum.map(&elem(&1, 1)) |> Levels.sum(),
            places: places,
            expiry: expiry(lot, today, soon_days(item))
          }
        end)
        |> Enum.sort_by(&lot_order/1)

      %{
        item: item,
        level: sum_levels(lots),
        expired: lots |> Enum.filter(&(&1.expiry == :expired)) |> sum_levels(),
        soon: lots |> Enum.filter(&(&1.expiry == :soon)) |> sum_levels(),
        below_zero:
          for(
            %{lot: lot, places: places} <- lots,
            {place, level} <- places,
            Decimal.negative?(level),
            do: {lot, place, level}
          ),
        lots: lots,
        short: short(item, lots, Map.get(wanted_of, item.id, []))
      }
    end
  end

  defp sum_levels(lots), do: lots |> Enum.map(& &1.level) |> Levels.sum()

  # The lot that expires first is at the top. A lot with no expiry date is
  # after the others.
  defp lot_order(%{lot: %{expires_on: nil} = lot}), do: {1, 0, lot.code || "", lot.id}

  defp lot_order(%{lot: lot}),
    do: {0, Date.to_gregorian_days(lot.expires_on), lot.code || "", lot.id}

  # The reorder levels that the stock is below. Stock that is past its
  # expiry date is of no use, so it does not count.
  defp short(item, lots, wanted) do
    good = Enum.reject(lots, &(&1.expiry == :expired))

    whole =
      if item.reorder_level,
        do: [%{location_id: nil, wanted: item.reorder_level, level: sum_levels(good)}],
        else: []

    places =
      for %{location_id: location_id, quantity: quantity} <- wanted do
        level =
          for(%{places: places} <- good, {^location_id, level} <- places, do: level)
          |> Levels.sum()

        %{location_id: location_id, wanted: quantity, level: level}
      end

    Enum.filter(whole ++ places, &(Decimal.compare(&1.level, &1.wanted) == :lt))
  end

  @doc """
  Where a lot is with its expiry date on a day of the organisation:
  `:expired` after the date, `:soon` in the `soon_days` before it and on it,
  `:later` before that, and `:none` for a lot with no expiry date.
  `soon_days` is 30 when the caller gives none.
  """
  @spec expiry(map, Date.t(), non_neg_integer) :: :expired | :soon | :later | :none
  def expiry(lot, today, soon_days \\ @soon_days)
  def expiry(%{expires_on: nil}, _today, _soon_days), do: :none

  def expiry(%{expires_on: %Date{} = expires_on}, %Date{} = today, soon_days) do
    case Date.diff(expires_on, today) do
      days when days < 0 -> :expired
      days when days <= soon_days -> :soon
      _days -> :later
    end
  end

  @doc "The days before its expiry date in which a lot of an item expires soon."
  @spec soon_days(map) :: non_neg_integer
  def soon_days(%{category: %{soon_days: days}}) when is_integer(days), do: days
  def soon_days(_item), do: @soon_days

  @doc """
  The last stock movements of an item, the newest first by the time that
  each happened, each with its lot. `limit` is 100 when the caller gives
  none.
  """
  def history(item_id, opts \\ []) do
    {limit, opts} = Keyword.pop(opts, :limit, 100)

    with {:ok, lots} <- Lot |> Ash.Query.filter(item_id == ^item_id) |> Ash.read(opts) do
      lot_of = Map.new(lots, &{&1.id, &1})

      with {:ok, movements} <-
             StockMovement
             |> Ash.Query.filter(lot_id in ^Map.keys(lot_of))
             |> Ash.Query.sort(happened_at: :desc, id: :desc)
             |> Ash.Query.limit(limit)
             |> Ash.read(opts) do
        {:ok, Enum.map(movements, &Map.put(&1, :lot, lot_of[&1.lot_id]))}
      end
    end
  end

  @doc """
  Gives an item a reorder level in one location, changes the one that it
  has, or removes it when `quantity` is `nil`. Returns the level, or `nil`
  after a removal.
  """
  def set_reorder_level(item_id, location_id, quantity, opts \\ []) do
    existing =
      ReorderLevel
      |> Ash.Query.filter(item_id == ^item_id and location_id == ^location_id)
      |> Ash.read_one(opts)

    case {existing, quantity} do
      {{:error, error}, _quantity} ->
        {:error, error}

      {{:ok, nil}, nil} ->
        {:ok, nil}

      {{:ok, nil}, quantity} ->
        ReorderLevel
        |> Ash.Changeset.for_create(
          :set,
          %{item_id: item_id, location_id: location_id, quantity: quantity},
          opts
        )
        |> Ash.create()

      {{:ok, level}, nil} ->
        with :ok <- Ash.destroy(level, [action: :clear] ++ opts), do: {:ok, nil}

      {{:ok, level}, quantity} ->
        level |> Ash.Changeset.for_update(:change, %{quantity: quantity}, opts) |> Ash.update()
    end
  end

  @doc """
  Whether a role can run an action of a resource of this domain at all. A
  page asks this to decide what to show. The policy decides when the action
  runs.
  """
  @spec role_can?(atom | nil, :item | :supplier | :lot | :movement | :reorder_level, atom) ::
          boolean
  def role_can?(role, subject, action) do
    resource =
      case subject do
        :item -> Item
        :supplier -> Supplier
        :lot -> Lot
        :movement -> StockMovement
        :reorder_level -> ReorderLevel
      end

    Rescord.Accounts.granted?(role, resource, action)
  end
end
