defmodule RescordWeb.CinderFixtures do
  @moduledoc """
  A resource in memory, and a LiveView that shows it through Cinder.
  `RescordWeb.CinderTest` reads the markup that Cinder renders for them.
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

  defmodule Row do
    @moduledoc false
    # Not `Rescord.Resource`: this resource has no table in PostgreSQL.
    use Ash.Resource, domain: RescordWeb.CinderFixtures.Domain, data_layer: Ash.DataLayer.Ets

    actions do
      defaults [:read, create: [:name, :kind, :desexed, :arrived_on]]
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
      attribute :kind, :atom, public?: true, constraints: [one_of: [:dog, :cat]]
      attribute :desexed, :boolean, public?: true
      attribute :arrived_on, :date, public?: true
    end
  end

  defmodule Live do
    @moduledoc false
    use Phoenix.LiveView

    alias RescordWeb.CinderFixtures.Row

    @shapes %{"table" => :table, "list" => :list, "grid" => :grid}

    def mount(_params, session, socket) do
      {:ok, assign(socket, shape: Map.fetch!(@shapes, session["shape"]), resource: Row)}
    end

    def render(assigns) do
      ~H"""
      <Cinder.collection
        id="rows"
        resource={@resource}
        actor={nil}
        layout={@shape}
        page_size={[default: 2, options: [2, 5]]}
        search={[placeholder: "Search"]}
      >
        <:col :let={row} field="name" filter sort search>{row.name}</:col>
        <:col :let={row} field="kind" filter sort>{row.kind}</:col>
        <:col :let={row} field="desexed" filter>{row.desexed}</:col>
        <:col :let={row} field="arrived_on" filter>{row.arrived_on}</:col>
        <:item :let={row}>
          <article>{row.name}</article>
        </:item>
      </Cinder.collection>
      """
    end
  end
end
