defmodule Rescord.Journal.Validations.UnitOfKind do
  @moduledoc """
  The unit of a measurement is one of the units of its kind (the maintainer,
  18 November 2026). A kind with no unit in its list accepts each unit.

  The kind is the argument `measure_kind_id`, or the kind of the measurement
  that a correction changes. The validation runs after the policy, so a
  person who cannot write the entry gets the answer of the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Journal.Measurement

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    with unit_id when is_binary(unit_id) <- argument(changeset, :unit_id),
         kind_id when is_binary(kind_id) <- kind_id(changeset),
         [_ | _] = unit_ids <- Rescord.Lists.unit_ids_of_kind(kind_id, options(changeset)),
         false <- unit_id in unit_ids do
      {:error, field: :unit_id, message: "is not a unit of this kind of measurement"}
    else
      _fits -> :ok
    end
  end

  defp kind_id(changeset) do
    case argument(changeset, :measure_kind_id) do
      nil ->
        case changeset.data do
          %{id: id} when is_binary(id) ->
            Measurement
            |> Ash.Query.filter(entry_id == ^id)
            |> Ash.read_one!(options(changeset))
            |> case do
              nil -> nil
              measurement -> measurement.measure_kind_id
            end

          _new ->
            nil
        end

      kind_id ->
        kind_id
    end
  end

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
