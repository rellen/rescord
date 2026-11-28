defmodule Rescord.Lists.Validations.StandardUnit do
  @moduledoc """
  The standard unit of a measure kind is a unit of the organisation, and
  one of the units of the kind when the kind names some (ADR 0094).

  The validation holds for the action that sets the standard unit and for
  the action that sets the units: a list of units that leaves the standard
  unit out is refused, so a person changes the standard unit first.
  """

  use Ash.Resource.Validation

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    standard_id = Ash.Changeset.get_attribute(changeset, :standard_unit_id)
    unit_ids = Ash.Changeset.get_attribute(changeset, :unit_ids) || []

    cond do
      is_nil(standard_id) ->
        :ok

      unit_ids != [] and standard_id not in unit_ids ->
        if Ash.Changeset.changing_attribute?(changeset, :standard_unit_id) do
          {:error,
           field: :standard_unit_id,
           message: "is not one of the units of this kind of measurement"}
        else
          {:error,
           field: :unit_ids,
           message: "must keep the standard unit of the kind. Change the standard unit first"}
        end

      Ash.Changeset.changing_attribute?(changeset, :standard_unit_id) and
          not unit?(standard_id, changeset) ->
        {:error, field: :standard_unit_id, message: "is not a unit of the organisation"}

      true ->
        :ok
    end
  end

  defp unit?(id, changeset) do
    base = [tenant: changeset.tenant, authorize?: false, not_found_error?: false]

    options =
      case changeset.as_of do
        %DateTime{} = instant -> [as_of: instant] ++ base
        _not_set -> base
      end

    match?({:ok, %{}}, Ash.get(Rescord.Lists.Unit, id, options))
  end
end
