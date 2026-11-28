defmodule RescordWeb.RubyConversationsLive do
  @moduledoc """
  "Your conversations" with Ruby (ADR 0069), at
  `/o/<short name>/ruby/conversations`: the conversations of the person, the
  newest first, in pages, with a search in their names. Each is a card that
  opens it, with the time of its last message, the record that it is about
  and how many messages it holds.

  The page says who reads a conversation and how long it stays, and has
  the removal of all of them, behind a `<details>` that says what stays.

  Like the page of Ruby, it is there only for a person whom
  `Rescord.Ruby.available?/2` lets ask Ruby: for anybody else the address
  answers as a page that is not there. It reads only the conversations of
  the person (the action `mine`), also for a person with the power
  `settings`.
  """

  use RescordWeb, :live_view
  use Cinder.UrlSync

  alias Rescord.Ruby
  alias RescordWeb.{NotFound, RubyWords}

  @impl true
  def mount(_params, _session, socket) do
    unless socket.assigns.ruby?, do: raise(NotFound)

    {:ok,
     socket
     |> assign(
       page_title: "Your conversations",
       days: Ruby.settings(socket.assigns.organisation).retention_days,
       problems: []
     )
     |> assign_about()}
  end

  # The names of the records that the conversations are about, read once
  # as the person when the page is connected: a card does not read. Only
  # the field `about` of each conversation is read. A record that the
  # person cannot read any more has no name here, and its card says
  # nothing of it.
  defp assign_about(socket) do
    if connected?(socket), do: read_about(socket), else: assign(socket, :about, %{})
  end

  defp read_about(socket) do
    refs =
      for %{about: ref} <-
            Ruby.conversations!(Keyword.put(options(socket), :query, select: [:about])),
          is_binary(ref),
          uniq: true,
          do: ref

    about =
      for ref <- refs, {:ok, about} <- [Ruby.about(ref, options(socket))], into: %{} do
        {ref, about}
      end

    assign(socket, :about, about)
  end

  defp options(socket),
    do: [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

  @impl true
  def handle_event("remove-all", _params, socket) do
    case Ruby.remove_conversations(options(socket)) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Your conversations with Ruby are removed.")
         |> push_navigate(to: start_path(socket))}

      {:error, _errors} ->
        {:noreply, assign(socket, problems: ["Rescord could not remove your conversations."])}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp start_path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/ruby"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:ruby}
    >
      <.header icon={Icons.section(:ruby)}>
        <:crumb navigate={~p"/o/#{@organisation.short_name}/ruby"}>Ruby</:crumb>
        Your conversations
        <:subtitle>
          The administrators of {@organisation.name} can read what you ask Ruby. No other
          member can. Rescord removes a conversation {RubyWords.days(@days)} after its last
          message.
        </:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/ruby"} data-variant="primary">
            <.icon name="plus" /> New conversation
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section id="conversations" aria-label="Your conversations">
        <Cinder.collection
          id="ruby-conversations"
          layout={:list}
          query={
            Ruby.query_to_conversations(
              actor: @current_user,
              tenant: @organisation,
              query: [load: [:message_count]]
            )
          }
          actor={@current_user}
          tenant={@organisation}
          url_state={@url_state}
          page_size={[default: 25, options: [25, 50, 100]]}
          show_sort={false}
          search={[label: "Find a conversation", placeholder: "A word of its name"]}
        >
          <:col field="title" search />
          <:empty :let={found}>
            <p :if={found.filtered?}>No conversation has that in its name.</p>
            <p :if={not found.filtered?}>
              You have no conversation with Ruby yet.
              <.link navigate={~p"/o/#{@organisation.short_name}/ruby"}>Ask Ruby something</.link>
            </p>
          </:empty>
          <:item :let={conversation}>
            <.link
              navigate={conversation_path(@organisation, conversation)}
              id={"conversation-#{conversation.id}"}
              data-conversation
            >
              <span>
                {RubyWords.title(conversation)}
                <small>
                  {RubyWords.conversation_line(
                    conversation,
                    @about[conversation.about],
                    @organisation
                  )}
                </small>
              </span>
            </.link>
          </:item>
        </Cinder.collection>
      </section>

      <.confirm id="remove-all" summary="Remove all of your conversations">
        <p>
          Rescord deletes each of your conversations with Ruby for real, with their messages.
          Nobody can bring them back. What Ruby used of the allowance of {@organisation.name} stays, as counts with no words.
        </p>
        <.button type="button" variant="danger" phx-click="remove-all">
          Remove all of your conversations
        </.button>
      </.confirm>
    </Layouts.app>
    """
  end

  # A link to a conversation opens it at its newest message.
  defp conversation_path(organisation, conversation),
    do: ~p"/o/#{organisation.short_name}/ruby/#{conversation.id}" <> "#newest"
end
