defmodule RescordWeb.HousingLive do
  @moduledoc """
  The housing of an organisation, at `/o/<short name>/housing`.

  The page draws the locations as a tree: each location is a card, and the
  locations inside it are smaller cards in that card. The same page serves
  each shape of housing, because an organisation defines its own kinds of
  location (ADR 0029).

  Each member reads the housing. An administrator adds a location here.
  """

  use RescordWeb, :live_view

  import RescordWeb.LocationComponents

  alias Rescord.{Lists, Locations}

  @impl true
  def mount(_params, _session, socket) do
    options = options(socket)
    {:ok, tree} = Locations.tree(options)
    {:ok, kinds} = Lists.offered_values(:location_kind, options)

    {:ok,
     assign(socket,
       page_title: "Housing",
       problems: [],
       tree: tree,
       kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}),
       places:
         for(
           {node, depth} <- Locations.flat(tree),
           do: {String.duplicate("– ", depth) <> node.location.name, node.location.id}
         ),
       can_add?: Locations.role_can?(socket.assigns.role, :location, :add),
       form:
         to_form(%{"name" => "", "kind_id" => "", "capacity" => "", "parent_id" => ""},
           as: :location
         )
     )}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  @impl true
  def handle_event("add", %{"location" => fields}, socket) when is_map(fields) do
    attributes = %{
      name: non_blank(fields["name"]),
      kind_id: non_blank(fields["kind_id"]),
      capacity: non_blank(fields["capacity"]),
      parent_id: non_blank(fields["parent_id"])
    }

    case Locations.add_location(attributes, options(socket)) do
      {:ok, _location} ->
        {:noreply,
         push_navigate(socket, to: ~p"/o/#{socket.assigns.organisation.short_name}/housing")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Rescord.Accounts.error_messages(error),
           form: typed_form(fields, as: :location)
         )}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      section={:housing}
    >
      <.header icon={Icons.section(:housing)}>
        Housing
        <:subtitle>Where the residents of {@organisation.name} live</:subtitle>
        <:actions>
          <RescordWeb.ReportComponents.report_link
            id="housing-report"
            href={~p"/o/#{@organisation.short_name}/reports/housing.pdf"}
          >
            Housing report (PDF)
          </RescordWeb.ReportComponents.report_link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p :if={@tree == []}>There is no location yet.</p>
      <.place :for={node <- @tree} node={node} organisation={@organisation} level={2} />

      <.new_location :if={@can_add?} form={@form} kinds={@kinds} places={@places} />
    </Layouts.app>
    """
  end
end
