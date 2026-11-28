defmodule Rescord.Residents.Changes.WriteFacts do
  @moduledoc """
  Writes the facts that `register` and `revise` of a resident take as
  arguments: the name, the desex status, the ties to the breeds, the colours
  and the temperaments, and the arrival.

  The facts are other resources. This change writes them after the resident,
  in the same transaction and as of the same instant, so a fault in one of
  them leaves nothing behind.

    * An argument that is not given, or is `nil`, changes nothing.
    * A fact that has the same value already gets no new version.
    * A list of values replaces the ties: the change adds each value that is
      new, and ends the tie of each value that is not in the list.

  The policy of the resident decided that the actor can run the action. The
  facts are a part of that action, so the change writes them with no second
  decision, and names the actor for the paper trail.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Residents.{
    Arrival,
    ResidentBreed,
    ResidentColour,
    ResidentDesexStatus,
    ResidentName,
    ResidentTemperament
  }

  @ties [
    {:breed_ids, ResidentBreed, :breed_id},
    {:colour_ids, ResidentColour, :colour_id},
    {:temperament_ids, ResidentTemperament, :temperament_id}
  ]

  # The change reads and writes through Ash only, as of the instant of the
  # action, and it does not read the clock.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> check_arrival()
    |> Ash.Changeset.after_action(fn changeset, resident ->
      options = options(changeset, context)

      with :ok <- write_one(ResidentName, :name, argument(changeset, :name), resident, options),
           :ok <-
             write_one(
               ResidentDesexStatus,
               :status,
               argument(changeset, :desex_status),
               resident,
               options
             ),
           :ok <- write_ties(changeset, resident, options),
           :ok <- write_arrival(changeset, resident, options) do
        {:ok, resident}
      end
    end)
  end

  defp options(changeset, context) do
    base = [
      actor: context.actor,
      tenant: changeset.tenant,
      context: Rescord.Correlation.context(changeset),
      authorize?: false
    ]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      %Ash.Range{} = period -> [as_of: period] ++ base
      _not_set -> base
    end
  end

  defp argument(changeset, name) do
    case Ash.Changeset.fetch_argument(changeset, name) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  # An arrival has a kind and a date, or the resident has no arrival yet.
  defp check_arrival(changeset) do
    case {argument(changeset, :arrival_kind), argument(changeset, :arrived_on)} do
      {nil, %Date{}} ->
        Ash.Changeset.add_error(changeset,
          field: :arrival_kind,
          message: "is necessary with the date of the arrival"
        )

      {kind, nil} when not is_nil(kind) ->
        Ash.Changeset.add_error(changeset,
          field: :arrived_on,
          message: "is necessary with the kind of the arrival"
        )

      _both_or_neither ->
        changeset
    end
  end

  # A fact of which a resident has one: the name, the desex status.
  defp write_one(_resource, _attribute, nil, _resident, _options), do: :ok

  defp write_one(resource, attribute, value, resident, options) do
    resource
    |> Ash.Query.filter(resident_id == ^resident.id)
    |> Ash.read_one(options)
    |> case do
      {:ok, nil} ->
        resource
        |> Ash.Changeset.for_create(
          :set,
          %{attribute => value, resident_id: resident.id},
          options
        )
        |> Ash.create()
        |> done()

      {:ok, %{^attribute => ^value}} ->
        :ok

      {:ok, record} ->
        record
        |> Ash.Changeset.for_update(:change, %{attribute => value}, options)
        |> Ash.update()
        |> done()

      {:error, error} ->
        {:error, error}
    end
  end

  defp write_ties(changeset, resident, options) do
    Enum.reduce_while(@ties, :ok, fn {name, resource, value_id}, :ok ->
      case replace_ties(resource, value_id, argument(changeset, name), resident, options) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp replace_ties(_resource, _value_id, nil, _resident, _options), do: :ok

  defp replace_ties(resource, value_id, wanted, resident, options) do
    wanted = Enum.uniq(wanted)

    with {:ok, ties} <-
           resource |> Ash.Query.filter(resident_id == ^resident.id) |> Ash.read(options) do
      have = Enum.map(ties, &Map.fetch!(&1, value_id))
      stale = Enum.reject(ties, &(Map.fetch!(&1, value_id) in wanted))

      with :ok <- each(stale, &(&1 |> Ash.destroy(options) |> done())) do
        each(wanted -- have, fn id ->
          resource
          |> Ash.Changeset.for_create(:add, %{value_id => id, resident_id: resident.id}, options)
          |> Ash.create()
          |> done()
        end)
      end
    end
  end

  defp write_arrival(changeset, resident, options) do
    case argument(changeset, :arrival_kind) do
      nil ->
        :ok

      kind ->
        Arrival
        |> Ash.Changeset.for_create(
          :record,
          %{
            resident_id: resident.id,
            kind: kind,
            arrived_on: argument(changeset, :arrived_on),
            note: argument(changeset, :arrival_note)
          },
          options
        )
        |> Ash.create()
        |> done()
    end
  end

  defp each(items, write) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case write.(item) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp done(:ok), do: :ok
  defp done({:ok, _record}), do: :ok
  defp done({:error, error}), do: {:error, error}
end
