defmodule RescordWeb.CalendarLive do
  @moduledoc """
  The calendar feeds of a person in an organisation, at
  `/o/<short name>/calendar` (ADR 0074).

  A person whose role has the power `calendar` makes a feed: a calendar
  that their calendar app subscribes to, with the tasks and the dates that
  they choose. The page shows the address of a new feed one time, because
  Rescord stores only the hash of its token. A person revokes a feed, and
  its address reads nothing from then on.

  A person with the power `members` also sees the feeds of the other
  members, with when a calendar app last read each, and can revoke one.

  A root user who is not a member has no feed here: a feed belongs to a
  member.
  """

  use RescordWeb, :live_view

  import RescordWeb.CalendarComponents

  alias Rescord.{Accounts, Calendars}
  alias RescordWeb.{CalendarEvents, CalendarWords}

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.role

    {:ok,
     socket
     |> assign(
       page_title: "Calendar feeds",
       problems: [],
       new: nil,
       member?: not is_nil(socket.assigns.member),
       can_subscribe?: Calendars.role_can?(role, :subscribe),
       reads_each?: Calendars.role_reads_each?(role),
       limit: Calendars.feeds_for_each_member()
     )
     |> assign_form(%{})
     |> assign_feeds()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_form(socket, fields) do
    start = %{"name" => socket.assigns.organisation.name, "tasks" => "mine"}
    assign(socket, form: typed_form(Map.merge(start, text_fields(fields)), as: :feed))
  end

  defp assign_feeds(socket) do
    user = socket.assigns.current_user
    {:ok, own} = Calendars.feeds_of(user, options(socket))

    others =
      if socket.assigns.reads_each? do
        {:ok, others} = Calendars.feeds_of_others(user, options(socket))
        others
      else
        []
      end

    assign(socket, feeds: own, others: others)
  end

  @impl true
  def handle_event("subscribe", %{"feed" => fields}, socket) when is_map(fields) do
    fields = text_fields(fields)

    with {:ok, tasks} <- tasks(fields),
         {:ok, feed} <-
           Calendars.subscribe(
             %{
               name: fields["name"],
               tasks: tasks,
               with_returns: fields["with_returns"] == "true",
               with_expiry: fields["with_expiry"] == "true",
               with_notes: fields["with_notes"] == "true"
             },
             options(socket)
           ) do
      address = CalendarEvents.address(socket.assigns.organisation, Calendars.token(feed))

      {:noreply,
       socket
       |> assign(problems: [], new: %{id: feed.id, name: feed.name, address: address})
       |> assign_form(%{})
       |> assign_feeds()}
    else
      {:error, words} when is_binary(words) ->
        {:noreply, socket |> assign(problems: [words]) |> assign_form(fields)}

      {:error, error} ->
        {:noreply,
         socket |> assign(problems: Accounts.error_messages(error)) |> assign_form(fields)}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.feeds ++ socket.assigns.others, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      feed ->
        case Calendars.revoke_feed(feed, options(socket)) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "The feed #{feed.name} is revoked.")
             |> forget_address(feed)
             |> assign_feeds()}

          {:error, error} ->
            {:noreply,
             socket |> assign(problems: Accounts.error_messages(error)) |> assign_feeds()}
        end
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp tasks(fields) do
    case CalendarWords.tasks_of(fields["tasks"]) do
      {:ok, tasks} -> {:ok, tasks}
      :error -> {:error, "Choose which tasks the feed holds."}
    end
  end

  # The address of a feed that was revoked reads nothing: the page drops it.
  defp forget_address(%{assigns: %{new: %{id: id}}} = socket, %{id: id}),
    do: assign(socket, new: nil)

  defp forget_address(socket, _feed), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:tasks}
    >
      <.header icon={Icons.section(:calendar)}>
        Calendar feeds
        <:subtitle>
          The tasks and the dates of {@organisation.name}, in your calendar app.
        </:subtitle>
      </.header>

      <p>
        A feed is a calendar at a secret address. Your calendar app subscribes to it, and
        shows the tasks and the dates beside the rest of your day. It reads what you can
        read in Rescord, and it changes nothing.
      </p>

      <.new_address :if={@new} name={@new.name} address={@new.address} />

      <.own_feeds :if={@member?} feeds={@feeds} organisation={@organisation} />

      <.new_feed
        :if={@member? and @can_subscribe?}
        form={@form}
        problems={@problems}
        limit={@limit}
      />

      <p :if={!@member?} id="not-a-member">
        You are not a member of {@organisation.name}, so you have no feed here. A feed
        belongs to a member.
      </p>

      <p :if={@member? and !@can_subscribe?} id="no-calendar">
        Your role cannot make a calendar feed. An administrator can allow it for your role on
        the page of the roles.
      </p>

      <.other_feeds :if={@reads_each?} feeds={@others} organisation={@organisation} />

      <.how_to />
    </Layouts.app>
    """
  end
end
