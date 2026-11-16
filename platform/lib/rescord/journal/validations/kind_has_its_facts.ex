defmodule Rescord.Journal.Validations.KindHasItsFacts do
  @moduledoc """
  A new journal entry has what its kind needs: a diagnosis names a
  condition, a measurement has a kind and a value, a procedure has a kind, a
  vaccination names a vaccine, and a prescription names a medication. An
  entry of each other kind has words, or it would say nothing.

  An addendum adds words to an earlier entry, so it needs words and not the
  facts of its kind.
  """

  use Ash.Resource.Validation

  @needs %{
    diagnosis: [:condition_id],
    measurement: [:measure_kind_id, :value],
    procedure: [:procedure_kind_id],
    vaccination: [:vaccine],
    prescription: [:medication],
    dose: []
  }

  @impl true
  def temporal_safe?(_opts), do: true

  @doc "The arguments that a kind needs, or `nil` for a kind that needs words."
  def needs(kind), do: Map.get(@needs, kind)

  @impl true
  def validate(changeset, _opts, _context) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)

    needs = if Ash.Changeset.get_attribute(changeset, :follows_id), do: nil, else: needs(kind)

    case needs do
      nil ->
        if is_nil(kind) or present?(Ash.Changeset.get_attribute(changeset, :note)),
          do: :ok,
          else: {:error, field: :note, message: "is required for an entry of this kind"}

      arguments ->
        case Enum.find(arguments, &(not present?(Ash.Changeset.get_argument(changeset, &1)))) do
          nil -> :ok
          missing -> {:error, field: missing, message: "is required for an entry of this kind"}
        end
    end
  end

  defp present?(nil), do: false
  defp present?(text) when is_binary(text), do: String.trim(text) != ""
  defp present?(_value), do: true
end
