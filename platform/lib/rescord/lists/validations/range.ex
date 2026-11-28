defmodule Rescord.Lists.Validations.Range do
  @moduledoc """
  The range of a measure kind (ADR 0117): the lowest is not above the
  highest, and a kind takes a range only with a standard unit, in which the
  range is. With no standard unit, Rescord cannot compare two measurements
  of different units.
  """

  use Ash.Resource.Validation

  # The validation reads the changeset only.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    lowest = Ash.Changeset.get_attribute(changeset, :lowest)
    highest = Ash.Changeset.get_attribute(changeset, :highest)
    standard_id = Ash.Changeset.get_attribute(changeset, :standard_unit_id)

    cond do
      is_nil(lowest) and is_nil(highest) ->
        :ok

      is_nil(standard_id) ->
        {:error,
         field: :lowest,
         message: "needs a standard unit of the kind first: the range is in that unit"}

      lowest && highest && Decimal.compare(lowest, highest) == :gt ->
        {:error, field: :highest, message: "must not be below the lowest"}

      true ->
        :ok
    end
  end
end
