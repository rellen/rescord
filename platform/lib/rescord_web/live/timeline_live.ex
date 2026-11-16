defmodule RescordWeb.TimelineLive do
  @moduledoc """
  The timeline of a resident, at
  `/o/<short name>/residents/<id>/timeline` (ADR 0035): its journal entries
  together with the changes that Rescord recorded, the newest first.

  The page reads only. A member writes an entry on the journal page, and
  records a change on the page of the resident, of a group or of a location.
  """

  use RescordWeb, :live_view

  alias Rescord.{Accounts, Journal, Locations, Residents}
  alias RescordWeb.{JournalWords, TimelineWords}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = resident} <- Residents.resident(id, [load: [:name]] ++ options) do
      {:ok, events} = Journal.timeline(id, options)
      {:ok, members} = Accounts.members([load: [:email]] ++ options)
      {:ok, tree} = Locations.tree(options)
      {:ok, groups} = Residents.groups_with_facts(options)

      {:ok,
       assign(socket,
         resident: resident,
         page_title: "Timeline of #{name(resident)}",
         events: events,
         people: Map.new(members, &{&1.user_id, to_string(&1.email)}),
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

  defp when_words(organisation, instant),
    do: JournalWords.time(Accounts.local_time(organisation, instant))

  # The person of an event, or `nil` for an event that has none on record.
  # A root user is not a member, and reads their own events as their own.
  defp person(_people, %{user_id: nil}, _user), do: nil

  defp person(people, %{user_id: id}, user) do
    cond do
      Map.has_key?(people, id) -> people[id]
      id == user.id -> to_string(user.email)
      true -> "a person who is not a member now"
    end
  end

  defp resident_path(organisation, resident),
    do: ~p"/o/#{organisation.short_name}/residents/#{resident.id}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Timeline of {name(@resident)}
        <:subtitle>
          The journal entries and the changes that Rescord recorded, the newest first
        </:subtitle>
        <:actions>
          <.link navigate={resident_path(@organisation, @resident)} data-variant="secondary">
            The resident
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
        <li :for={event <- @events} data-subject={event.subject}>
          <time datetime={DateTime.to_iso8601(event.at)}>
            {when_words(@organisation, event.at)}
          </time>
          <p>{TimelineWords.event(event, @names)}</p>
          <small :if={person = person(@people, event, @current_user)}>{person}</small>
        </li>
      </ol>
    </Layouts.app>
    """
  end
end
