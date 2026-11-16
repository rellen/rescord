defmodule Rescord.ResidentsFixtures do
  @moduledoc """
  Helpers for the tests of the residents: the lists of an organisation, and
  a resident.
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias Rescord.{Lists, Residents}

  @doc """
  Gives an organisation a small set of local values, and returns their ids
  in a map: `lists.species.guinea_pig`, `lists.breed.abyssinian`, and so on.
  A root user adds them, because a root user can do anything.
  """
  def lists!(organisation, root) do
    for {key, names} <- [
          species: ["Guinea pig", "Rabbit"],
          breed: ["Abyssinian", "Sheltie", "Rex"],
          colour: ["White", "Tan", "Black"],
          size_class: ["Small"],
          coat: ["Rough", "Smooth"],
          temperament: ["Shy", "Confident"],
          identifier_kind: ["Microchip", "Ear tag"],
          condition: ["Respiratory infection"],
          measure_kind: ["Weight", "Temperature"],
          procedure_kind: ["Desexing"],
          unit: ["g"],
          task_kind: ["Feed", "Medicate", "Clean"]
        ],
        into: %{} do
      values =
        for name <- names, into: %{} do
          {:ok, value} = Lists.add_local_value(key, name, actor: root, tenant: organisation)
          {name |> String.downcase() |> String.replace(" ", "_") |> String.to_atom(), value.id}
        end

      {key, values}
    end
  end

  @doc "Registers a resident. `attributes` adds to a guinea pig with a name and an arrival."
  def resident!(lists, options, attributes \\ %{}) do
    %{
      name: "Biscuit",
      species_id: lists.species.guinea_pig,
      sex: :male,
      arrival_kind: :surrender,
      arrived_on: Date.add(Date.utc_today(), -3)
    }
    |> Map.merge(attributes)
    |> Residents.register_resident!(options)
  end

  @doc "The labels of the values of a list of ties, in the order of the labels."
  def labels(ties, value) do
    ties |> Enum.map(&to_string(Map.fetch!(&1, value).label)) |> Enum.sort()
  end
end
