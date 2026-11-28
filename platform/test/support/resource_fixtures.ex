defmodule Rescord.ResourceFixtures do
  @moduledoc """
  Resources that `Rescord.ResourceTest` reads. They have no table: the test
  reads how they compiled.
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

  defmodule Plain do
    @moduledoc false
    use Rescord.Resource, domain: Rescord.ResourceFixtures.Domain

    postgres do
      table "plains"
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  defmodule Shared do
    @moduledoc false
    use Rescord.Resource, domain: Rescord.ResourceFixtures.Domain, shared?: true

    postgres do
      table "shareds"
    end

    attributes do
      uuid_primary_key :id
    end
  end

  defmodule Bare do
    @moduledoc false
    use Rescord.Resource,
      domain: Rescord.ResourceFixtures.Domain,
      temporal?: false,
      paper_trail?: false,
      archive?: false

    postgres do
      table "bares"
    end

    attributes do
      uuid_primary_key :id
    end
  end

  defmodule NoTable do
    @moduledoc false
    use Rescord.Resource, domain: Rescord.ResourceFixtures.Domain, table?: false

    actions do
      action :answer, :integer do
        run fn _input, _context -> {:ok, 42} end
      end
    end
  end

  defmodule Flow do
    @moduledoc false
    use Rescord.Resource,
      domain: Rescord.ResourceFixtures.Domain,
      temporal?: false,
      extensions: [AshStateMachine]

    postgres do
      table "flows"
    end

    state_machine do
      initial_states [:open]
      default_initial_state :open

      transitions do
        transition :finish, from: :open, to: :done
      end
    end

    paper_trail do
      ignore_attributes [:id]
    end

    actions do
      defaults [:read, create: []]

      update :finish do
        change transition_state(:done)
      end
    end

    attributes do
      uuid_primary_key :id
    end
  end
end
