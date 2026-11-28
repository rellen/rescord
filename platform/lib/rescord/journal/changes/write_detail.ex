defmodule Rescord.Journal.Changes.WriteDetail do
  @moduledoc """
  Writes the facts of a journal entry of a medical kind, from the arguments
  of `write` and `correct`: the condition of a diagnosis, the value of a
  measurement, and so on. The facts are another resource. This change writes
  them after the entry, in the same transaction and as of the same instant.

    * An argument that is not given changes nothing.
    * Facts that have the same values already get no new version.

  The policy of the entry decided that the actor can run the action. The
  facts are a part of that action, so the change writes them with no second
  decision, and names the actor for the paper trail.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Journal

  @details %{
    diagnosis: {Journal.Diagnosis, [:condition_id]},
    measurement: {Journal.Measurement, [:measure_kind_id, :value, :unit_id]},
    procedure: {Journal.Procedure, [:procedure_kind_id]},
    vaccination: {Journal.Vaccination, [:vaccine]},
    prescription: {Journal.Prescription, [:medication, :dose, :route, :starts_on, :ends_on]},
    dose: {Journal.Dose, [:prescription_id, :amount]}
  }

  # The change reads and writes through Ash only, as of the instant of the
  # action, and it does not read the clock.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, entry ->
      case Map.get(@details, entry.kind) do
        nil ->
          {:ok, entry}

        {resource, keys} ->
          given =
            for key <- keys,
                {:ok, value} <- [Ash.Changeset.fetch_argument(changeset, key)],
                not is_nil(value),
                into: %{},
                do: {key, value}

          case write(resource, given, entry, options(changeset, context)) do
            :ok -> {:ok, entry}
            {:error, error} -> {:error, error}
          end
      end
    end)
  end

  defp write(_resource, given, _entry, _options) when map_size(given) == 0, do: :ok

  defp write(resource, given, entry, options) do
    resource
    |> Ash.Query.filter(entry_id == ^entry.id)
    |> Ash.read_one(options)
    |> case do
      {:ok, nil} ->
        resource
        |> Ash.Changeset.for_create(:set, Map.put(given, :entry_id, entry.id), options)
        |> Ash.create()
        |> done()

      {:ok, detail} ->
        if Enum.all?(given, fn {key, value} -> same?(Map.fetch!(detail, key), value) end) do
          :ok
        else
          detail |> Ash.Changeset.for_update(:change, given, options) |> Ash.update() |> done()
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp same?(%Decimal{} = one, %Decimal{} = other), do: Decimal.equal?(one, other)
  defp same?(one, other), do: one == other

  defp done({:ok, _record}), do: :ok
  defp done({:error, error}), do: {:error, error}

  defp options(changeset, context) do
    base = [
      actor: context.actor,
      tenant: changeset.tenant,
      context: Map.take(changeset.context, [:shared]),
      authorize?: false
    ]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
