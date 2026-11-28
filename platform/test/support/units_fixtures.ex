defmodule Rescord.UnitsFixtures do
  @moduledoc """
  A resource in memory that has a quantity and a unit as attributes, and an
  action with quantities as arguments. `Rescord.Units.TypesTest` reads how
  the two Ash types behave in a resource (ADR 0071).
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule Bottle do
    @moduledoc false
    # Not `Rescord.Resource`: this resource has no table in PostgreSQL.
    use Ash.Resource, domain: Rescord.UnitsFixtures.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :fill do
        accept [:strength, :counted_in]
      end

      update :change do
        accept [:strength, :counted_in]
      end

      action :dose, Rescord.Units.Types.Quantity do
        argument :weight, Rescord.Units.Types.Quantity do
          allow_nil? false
          constraints dimension: :mass, positive?: true
        end

        argument :rate, Rescord.Units.Types.Quantity do
          allow_nil? false
          constraints dimension: {:mass, :mass}
        end

        run fn input, _context ->
          Rescord.Units.multiply(input.arguments.rate, input.arguments.weight)
        end
      end
    end

    attributes do
      uuid_primary_key :id

      attribute :strength, Rescord.Units.Types.Quantity do
        public? true
        constraints dimension: [{:mass, :volume}, {:mass, :tablet}], positive?: true
      end

      attribute :counted_in, Rescord.Units.Types.Unit do
        public? true
        constraints dimension: [:volume, :tablet]
      end
    end
  end
end
