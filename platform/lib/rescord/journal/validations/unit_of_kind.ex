defmodule Rescord.Journal.Validations.UnitOfKind do
  @moduledoc """
  The unit of a measurement fits its kind (`Rescord.Lists.units_for/2`).

    * A kind with a standard unit (ADR 0094): the measurement needs a unit,
      and the unit is the standard unit or one that Rescord converts to it.
    * A kind that names its units and has no standard unit (the
      maintainer, 18 November 2026): the unit is one of them, or the
      measurement has no unit.
    * A kind that names no unit and has no standard unit accepts each unit.

  The kind is the argument `measure_kind_id`, or the kind of the measurement
  that a correction changes, and the unit likewise. A correction that gives
  no kind and no unit is not checked: a person can put the value or the
  words of an old measurement right, whose unit a newer rule would refuse.

  The validation runs after the policy, so a person who cannot write the
  entry gets the answer of the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Journal.Measurement

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    given_unit = argument(changeset, :unit_id)
    given_kind = argument(changeset, :measure_kind_id)
    existing = if changeset.action_type == :update, do: existing(changeset)

    cond do
      changeset.action_type == :update and is_nil(given_unit) and is_nil(given_kind) ->
        :ok

      kind_id = given_kind || (existing && existing.measure_kind_id) ->
        fits(given_unit || (existing && existing.unit_id), kind_id, options(changeset))

      true ->
        :ok
    end
  end

  defp fits(unit_id, kind_id, options) do
    case Rescord.Lists.units_for(kind_id, options) do
      :any ->
        :ok

      {:of_kind, unit_ids} ->
        if is_nil(unit_id) or unit_id in unit_ids,
          do: :ok,
          else: {:error, field: :unit_id, message: "is not a unit of this kind of measurement"}

      {:standard, label, unit_ids} ->
        cond do
          is_nil(unit_id) ->
            # The name is in the message itself: the error of a fact of an
            # entry loses the values beside its message on the way out.
            {:error,
             field: :unit_id,
             message: "is needed: a measurement of this kind has a unit, such as #{label}"}

          unit_id in unit_ids ->
            :ok

          true ->
            {:error,
             field: :unit_id,
             message: "is not a unit that Rescord converts to #{label}, the unit of this kind"}
        end
    end
  end

  # The measurement that a correction changes, or `nil` for an entry of
  # another kind.
  defp existing(%{data: %{id: id}} = changeset) when is_binary(id) do
    Measurement
    |> Ash.Query.filter(entry_id == ^id)
    |> Ash.read_one!(options(changeset))
  end

  defp existing(_changeset), do: nil

  defp argument(changeset, name) do
    case Ash.Changeset.fetch_argument(changeset, name) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp options(changeset) do
    base = [tenant: changeset.tenant, authorize?: false]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
