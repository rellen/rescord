defmodule RescordWeb.OrganisationLive do
  @moduledoc """
  The first page of an organisation, at `/o/<short name>` (ADR 0065).

  The live session opens it only for a member of the organisation and for a
  root user. It says who the person is here, and then what needs somebody
  now: the tasks that are overdue or due today, the stock to count or to
  order, the residents that are expected or late back, the locations over
  their capacity, and the transfers that wait for an answer. A person sees
  what they can read and can act on, and each row leads to the page where
  they act. Below that, the page leads to each part of the organisation.

  The page reads again when a record of one of its parts changes
  (ADR 0096), so it shows at once what another member did. It also reads
  again each minute: the time alone makes a task overdue, and no write
  tells the page about it.
  """

  use RescordWeb, :live_view

  import RescordWeb.AttentionComponents

  alias Rescord.{Accounts, Attention}

  # The time between two reads of what needs somebody.
  @every :timer.minutes(1)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, members} = Accounts.members([load: [:email]] ++ options(socket))

    if connected?(socket), do: Process.send_after(self(), :read_again, @every)

    {:ok,
     socket
     |> assign(
       page_title: socket.assigns.organisation.name,
       members: Enum.map(members, &{to_string(&1.email), &1.user_id})
     )
     # Listen first, and then read: no change falls between the two.
     |> LiveChanges.listen(Attention.domains(), &assign_attention/1)
     |> assign_attention()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_attention(socket) do
    now = DateTime.utc_now()

    parts =
      Attention.parts(socket.assigns.organisation,
        actor: socket.assigns.current_user,
        role: socket.assigns.role,
        now: now
      )

    assign(socket, attention: parts, now: now)
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:read_again, socket) do
    Process.send_after(self(), :read_again, @every)
    {:noreply, assign_attention(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:home}
    >
      <.header icon={Icons.section(:home)}>
        {@organisation.name}
        <:subtitle>{role_words(@role)}</:subtitle>
      </.header>

      <.attention
        parts={@attention}
        organisation={@organisation}
        now={@now}
        members={@members}
        user={@current_user}
      />

      <nav aria-labelledby="parts-heading">
        <h2 id="parts-heading">The parts of {@organisation.name}</h2>
        <ul data-links>
          <li :for={{path, section, words} <- parts(@organisation.short_name, @ruby?)}>
            <.link navigate={path}>
              <.icon name={Icons.section(section)} /> {words}
            </.link>
          </li>
        </ul>
      </nav>
    </Layouts.app>
    """
  end

  defp role_words(:root), do: "You are a root user. You can do anything here."
  defp role_words(%{name: name}), do: "Your role in this organisation: #{name}."

  # The parts of an organisation, each with the shape that it has in the
  # menu too (`RescordWeb.Icons.section/1`). Ruby comes first, for a person
  # who can ask it.
  defp parts(org, ruby?) do
    ask = if ruby?, do: [{~p"/o/#{org}/ruby", :ruby, "Ask Ruby"}], else: []

    ask ++
      [
        {~p"/o/#{org}/tasks", :tasks, "See the tasks of today"},
        {~p"/o/#{org}/routines", :routines, "See the routines"},
        {~p"/o/#{org}/calendar", :calendar, "See the calendar feeds"},
        {~p"/o/#{org}/residents", :residents, "See the residents"},
        {~p"/o/#{org}/groups", :groups, "See the groups"},
        {~p"/o/#{org}/housing", :housing, "See the housing"},
        {~p"/o/#{org}/inventory", :inventory, "See the inventory"},
        {~p"/o/#{org}/expenses", :expenses, "See the expenses"},
        {~p"/o/#{org}/tools", :tools, "Use the tools"},
        {~p"/o/#{org}/reports", :reports, "Make a report"},
        {~p"/o/#{org}/lists", :lists, "See the lists of values"},
        {~p"/o/#{org}/members", :members, "See the members"},
        {~p"/o/#{org}/roles", :roles, "See the roles"},
        {~p"/o/#{org}/transfers", :transfers, "See the transfers"},
        {~p"/o/#{org}/partners", :partners, "See the partner refuges"},
        {~p"/o/#{org}/settings", :settings, "See the settings"},
        {~p"/o/#{org}/export", :export, "Export the data"}
      ]
  end
end
