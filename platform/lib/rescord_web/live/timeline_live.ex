defmodule RescordWeb.TimelineLive do
  @moduledoc """
  The timeline of a resident, at
  `/o/<short name>/residents/<id>/timeline` (ADR 0035): its journal entries
  together with the changes that Rescord recorded, the newest first.

  The page reads only. A member writes an entry on the journal page, and
  records a change on the page of the resident, of a group or of a location.
  """

  use RescordWeb, :live_view

  import RescordWeb.TimelineComponents

  alias Rescord.{Accounts, Journal, Locations, Residents}
  alias RescordWeb.TimelineWords

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = resident} <- Residents.resident(id, [load: [:name]] ++ options) do
      {:ok, events} = Journal.timeline(id, options)
      {:ok, tree} = Locations.tree(options)
      {:ok, groups} = Residents.groups_with_facts(options)

      {:ok,
       assign(socket,
         resident: resident,
         page_title: "Timeline of #{name(resident)}",
         events: events,
         people: Accounts.labels(options),
         names: %{
           locations:
             for({node, _depth} <- Locations.flat(tree), into: %{}) do
               {node.location.id, node.location.name}
             end,
           groups: Map.new(groups, &{&1.id, TimelineWords.group(&1)})
         }
       )}
    else
      _no_resident ->
        {:ok,
         socket
         |> put_flash(:error, "That resident is not in the register.")
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}
    end
  end

  # Ignore an event that this page does not know.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp name(resident), do: resident.name || "a resident with no name"

  defp resident_path(organisation, resident),
    do: ~p"/o/#{organisation.short_name}/residents/#{resident.id}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:residents}
    >
      <.header icon={Icons.section(:timeline)}>
        Timeline of {name(@resident)}
        <:subtitle>
          The journal entries and the changes that Rescord recorded, the newest first
        </:subtitle>
        <:actions>
          <.link navigate={resident_path(@organisation, @resident)} data-variant="secondary">
            <.icon name="chevron-left" /> The resident
          </.link>
          <.link
            navigate={resident_path(@organisation, @resident) <> "/journal"}
            data-variant="secondary"
          >
            The journal
          </.link>
        </:actions>
      </.header>

      <p :if={@events == []}>Nothing is on record for this resident yet.</p>

      <ol :if={@events != []} id="timeline">
        <.timeline_event
          :for={event <- @events}
          event={event}
          organisation={@organisation}
          names={@names}
          people={@people}
          current_user={@current_user}
        />
      </ol>
    </Layouts.app>
    """
  end
end
