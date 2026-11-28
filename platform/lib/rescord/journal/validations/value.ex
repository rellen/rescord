defmodule Rescord.Journal.Validations.Value do
  @moduledoc """
  The value of a measurement is one that can be true (ADR 0117):

    * A measurement in a unit of mass, length or volume is more than 0. A
      temperature can be below 0, and a count or a score can be 0, so the
      other units have no such rule.
    * A measurement of a kind with a range (`lowest` and `highest` of
      `Rescord.Lists.MeasureKind`, in its standard unit) is inside it, once
      converted to the standard unit. A unit that Rescord does not convert
      to the standard unit is not checked against the range.

  The kind, the value and the unit are the arguments, or those of the
  measurement that a correction changes. A correction that gives none of
  the three is not checked, so a person can put the words or the time of an
  old measurement right, whose value a newer range would refuse.

  The validation runs after the policy, so a person who cannot write the
  entry gets the answer of the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Journal.Measurement
  alias Rescord.Lists
  alias Rescord.Units

  @positive [:mass, :length, :volume]

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    given = Map.new([:value, :unit_id, :measure_kind_id], &{&1, argument(changeset, &1)})

    if changeset.action_type == :update and Enum.all?(Map.values(given), &is_nil/1) do
      :ok
    else
      existing = if changeset.action_type == :update, do: existing(changeset)
      pick = fn name -> given[name] || (existing && Map.get(existing, name)) end
      check(pick.(:value), pick.(:unit_id), pick.(:measure_kind_id), options(changeset))
    end
  end

  defp check(%Decimal{} = value, unit_id, kind_id, options) when is_binary(kind_id) do
    unit = known_unit(unit_id, options)

    if positive?(unit) and Decimal.compare(value, 0) != :gt do
      {:error, field: :value, message: "must be more than 0"}
    else
      in_range(value, unit, kind_id, options)
    end
  end

  defp check(_value, _unit_id, _kind_id, _options), do: :ok

  defp positive?(%Units.Unit{dimension: dimension}), do: dimension in @positive
  defp positive?(nil), do: false

  defp in_range(value, unit, kind_id, options) do
    with %{} = kind <- kind(kind_id, options),
         true <- kind.lowest != nil or kind.highest != nil,
         %{} = standard <- kind.standard_unit,
         {:ok, to} <- Lists.known_unit(standard),
         %{} = from <- unit,
         {:ok, converted} <- Units.convert(value, from, to) do
      if inside?(converted, kind.lowest, kind.highest),
        do: :ok,
        else: {:error, field: :value, message: message(kind, to_string(standard.label))}
    else
      # No range, no standard unit, or a unit that does not convert to it.
      _not_checked -> :ok
    end
  end

  defp inside?(value, lowest, highest) do
    (is_nil(lowest) or Decimal.compare(value, lowest) != :lt) and
      (is_nil(highest) or Decimal.compare(value, highest) != :gt)
  end

  # The words are in the message itself: the error of a fact of an entry
  # loses the values beside its message on the way out.
  defp message(kind, unit) do
    range =
      case {kind.lowest, kind.highest} do
        {lowest, nil} -> "at least #{plain(lowest)} #{unit}"
        {nil, highest} -> "at most #{plain(highest)} #{unit}"
        {lowest, highest} -> "#{plain(lowest)} #{unit} to #{plain(highest)} #{unit}"
      end

    "is outside the range of #{kind.label}: #{range}"
  end

  defp plain(value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp known_unit(nil, _options), do: nil

  defp known_unit(unit_id, options) do
    with {:ok, %{} = unit} <-
           Ash.get(Lists.Unit, unit_id, [not_found_error?: false, load: [:label]] ++ options),
         {:ok, known} <- Lists.known_unit(unit) do
      known
    else
      _unknown -> nil
    end
  end

  defp kind(kind_id, options) do
    case Ash.get(
           Lists.MeasureKind,
           kind_id,
           [not_found_error?: false, load: [:label, standard_unit: [:label]]] ++ options
         ) do
      {:ok, %{} = kind} -> kind
      _none -> nil
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
