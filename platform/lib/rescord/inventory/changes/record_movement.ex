defmodule Rescord.Inventory.Changes.RecordMovement do
  @moduledoc """
  Gives a new stock movement its kind, its sign, its author and its time,
  and holds the rule of the level (ADR 0034).

  ## Options

    * `kind` - the kind of the movement.
    * `direction` - `:in` for a movement that adds the argument `quantity`,
      `:out` for one that takes it, and `:count` for one that brings the
      level to the argument `counted`.

  ## The rules

    * The quantity of a movement in or out is more than zero. A count is
      zero or more.
    * The time is the time that the member gave, or the instant of the
      write. It is never after that instant.
    * A movement out takes no more than the level of the lot in that place.

  The change reads the lot with a lock before the write, in the transaction
  of the action. So two members do not take the same stock at the same
  time. With no user, the change sets no author, and the policy refuses
  the action.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Ash.Changeset
  alias Rescord.Inventory.{Levels, Lot, StockMovement}

  # The change reads through Ash only, and the level is that of now: a
  # movement is not written as of a past instant.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, opts, context) do
    direction = Keyword.fetch!(opts, :direction)

    changeset
    |> Changeset.force_change_attribute(:kind, Keyword.fetch!(opts, :kind))
    |> set_author(context.actor)
    |> set_time()
    |> check_amount(direction)
    |> Changeset.before_action(&set_quantity(&1, direction))
  end

  defp set_author(changeset, %Rescord.Accounts.User{id: id}),
    do: Changeset.force_change_attribute(changeset, :author_id, id)

  defp set_author(changeset, _actor), do: changeset

  defp set_time(changeset) do
    now = DateTime.utc_now()

    case Changeset.get_attribute(changeset, :happened_at) do
      nil ->
        Changeset.force_change_attribute(changeset, :happened_at, now)

      %DateTime{} = happened_at ->
        if DateTime.compare(happened_at, now) == :gt,
          do: Changeset.add_error(changeset, field: :happened_at, message: "cannot be after now"),
          else: changeset
    end
  end

  defp check_amount(changeset, :count) do
    case Changeset.get_argument(changeset, :counted) do
      %Decimal{} = counted ->
        if Decimal.negative?(counted),
          do:
            Changeset.add_error(changeset, field: :counted, message: "cannot be less than zero"),
          else: changeset

      _none ->
        changeset
    end
  end

  defp check_amount(changeset, _direction) do
    case Changeset.get_argument(changeset, :quantity) do
      %Decimal{} = quantity ->
        if Decimal.positive?(quantity),
          do: changeset,
          else:
            Changeset.add_error(changeset, field: :quantity, message: "must be more than zero")

      _none ->
        changeset
    end
  end

  # Runs in the transaction, before the write.
  defp set_quantity(%{valid?: false} = changeset, _direction), do: changeset

  defp set_quantity(changeset, direction) do
    internal = [tenant: changeset.tenant, authorize?: false]
    lot_id = Changeset.get_attribute(changeset, :lot_id)
    location_id = Changeset.get_attribute(changeset, :location_id)

    case lock(lot_id, internal) do
      {:ok, %Lot{}} ->
        level = level(lot_id, location_id, internal)
        quantity(changeset, direction, level)

      _no_lot ->
        Changeset.add_error(changeset,
          field: :lot_id,
          message: "is not a lot of this organisation"
        )
    end
  end

  defp quantity(changeset, :in, _level) do
    Changeset.force_change_attribute(
      changeset,
      :quantity,
      Changeset.get_argument(changeset, :quantity)
    )
  end

  defp quantity(changeset, :out, level) do
    quantity = Changeset.get_argument(changeset, :quantity)

    if Decimal.compare(quantity, level) == :gt do
      there = level |> Decimal.normalize() |> Decimal.to_string(:normal)

      Changeset.add_error(changeset,
        field: :quantity,
        message: "is more than the #{there} there. Count the place when that number is wrong"
      )
    else
      Changeset.force_change_attribute(changeset, :quantity, Decimal.negate(quantity))
    end
  end

  defp quantity(changeset, :count, level) do
    counted = Changeset.get_argument(changeset, :counted)
    Changeset.force_change_attribute(changeset, :quantity, Decimal.sub(counted, level))
  end

  defp lock(nil, _internal), do: {:ok, nil}

  defp lock(lot_id, internal) do
    Lot
    |> Ash.Query.filter(id == ^lot_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(internal)
  end

  defp level(lot_id, location_id, internal) do
    StockMovement
    |> Ash.Query.filter(lot_id == ^lot_id)
    |> Ash.Query.select([:lot_id, :location_id, :quantity])
    |> Ash.read!(internal)
    |> Levels.by_place()
    |> Levels.at(lot_id, location_id)
  end
end
