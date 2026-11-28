defmodule RescordWeb.RubyLive do
  @moduledoc """
  The page of Ruby (ADR 0069): the start of a new conversation, at
  `/o/<short name>/ruby`, and one conversation, at
  `/o/<short name>/ruby/<id>`. One LiveView holds both, so the first
  message of a new conversation patches the page and does not mount it
  again.

  The page is there only for a person whom `Rescord.Ruby.available?/2`
  lets ask Ruby. For anybody else the address answers as a page that is
  not there (`RescordWeb.NotFound`).

  The answer runs in a job of the server, and not in the page: a page
  that closes and opens again misses nothing. The page hears the reply on
  the topic of the conversation (`Rescord.Ruby.subscribe/2`): the whole
  text so far, which it turns into blocks of safe HTML, and the state of
  the reply. When the state changes, the page reads the conversation
  again, so it draws what the database holds, and two tabs of one member
  show the same thing.

  The messages are an assign, with a key for each: a conversation has a
  limit, and the page reads it whole. One `role="status"` says each change
  of the answer once.
  """

  use RescordWeb, :live_view

  alias Rescord.Ruby
  alias RescordWeb.{NotFound, RubyChatComponents, RubyMarkdown, RubyWords}

  # The last conversations that the start shows.
  @recent 3
  # The things to ask that the start shows.
  @asks 4

  @impl true
  def mount(_params, _session, socket) do
    unless socket.assigns.ruby?, do: raise(NotFound)

    {:ok,
     socket
     |> assign(page_title: "Ruby", conversation: nil, messages: [], answer: nil, said: nil)
     |> assign(:known, MapSet.new())
     |> assign(problems: [], recent: [], about: nil, asks: [])
     |> assign(refused: nil, allowance: nil, closed?: false, settings?: Ruby.sets?(scope(socket)))
     |> assign_form("")}
  end

  @impl true
  def handle_params(%{"conversation_id" => id}, _uri, socket) do
    case Ruby.conversation(id, scope(socket)) do
      {:ok, %{} = conversation} ->
        {:noreply, open(socket, conversation)}

      _not_theirs ->
        {:noreply,
         socket
         |> put_flash(:error, "There is no such conversation.")
         |> push_navigate(to: start_path(socket))}
    end
  end

  def handle_params(params, _uri, socket) do
    %{current_user: user, organisation: organisation} = socket.assigns
    about = about(params["about"], socket)

    {:noreply,
     socket
     |> leave()
     |> assign(about: about, asks: asks(user, organisation, about))
     |> assign(page_title: "Ruby", conversation: nil, messages: [], answer: nil, said: nil)
     |> assign(:known, MapSet.new())
     |> assign(problems: [], refused: nil, closed?: false, recent: recent(socket))}
  end

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
      data-ruby
      phx-disconnected={
        JS.remove_attribute("hidden", to: "#ruby-offline")
        |> JS.set_attribute({"disabled", ""}, to: "#ruby-send")
      }
      phx-connected={
        JS.set_attribute({"hidden", ""}, to: "#ruby-offline")
        |> JS.remove_attribute("disabled", to: "#ruby-send")
      }
    >
      <nav :if={@conversation} aria-label="Breadcrumb">
        <.link patch={~p"/o/#{@organisation.short_name}/ruby"}>Ruby</.link>
      </nav>

      <.header icon={Icons.section(:ruby)}>
        {if @conversation, do: RubyWords.title(@conversation), else: "Ruby"}
        <:subtitle :if={!@conversation}>The assistant of {@organisation.name}</:subtitle>
        <:actions :if={@conversation}>
          <.link patch={~p"/o/#{@organisation.short_name}/ruby"} data-variant="secondary">
            <.icon name="plus" /> New conversation
          </.link>
        </:actions>
      </.header>

      <RubyChatComponents.about :if={@about} about={@about} organisation={@organisation} />

      <RubyChatComponents.start
        :if={!@conversation}
        organisation={@organisation}
        asks={@asks}
        recent={@recent}
      />

      <section :if={@conversation} data-log aria-label="Conversation">
        <ol id="ruby-messages" data-chat>
          <li :for={message <- @messages} :key={message.id} id={"message-#{message.id}"}>
            <RubyChatComponents.message
              message={message}
              organisation={@organisation}
              known={@known}
              way_on?={is_nil(@answer) and is_nil(@refused) and message.id == List.last(@messages).id}
              settings?={@settings?}
            />
          </li>
        </ol>

        <RubyChatComponents.answer :if={@answer} answer={@answer} />

        <div id="newest" data-end></div>
      </section>

      <%!-- In the page from the start, so that a screen reader hears its first change. --%>
      <p role="status" data-quiet>{@said}</p>

      <div :if={@refused || @problems != []} data-problem>
        <RubyChatComponents.problem
          :if={@refused}
          reason={@refused}
          organisation={@organisation}
          settings?={@settings?}
          again={:form}
          allowance={@allowance}
        />
        <.problems list={@problems} />
      </div>

      <RubyChatComponents.composer
        form={@form}
        answering?={@answer != nil}
        closed?={@closed?}
        organisation={@organisation}
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("draft", %{"message" => %{"text" => text}}, socket) when is_binary(text),
    do: {:noreply, assign_form(socket, text)}

  def handle_event("send", %{"message" => %{"text" => text}}, socket),
    do: {:noreply, say(socket, non_blank(text))}

  # A thing to ask: the button sends its words.
  def handle_event("ask", %{"text" => text}, socket), do: {:noreply, say(socket, non_blank(text))}

  # Stop names the message of the member, so it works before the reply
  # has a row. The page changes when the topic says that the reply stopped.
  # "Try again" sends the message of the member again: one of this
  # conversation, by its id.
  def handle_event("again", %{"id" => id}, %{assigns: %{messages: messages}} = socket)
      when is_binary(id) do
    with %{source: :ruby, response_to_id: ^id, reason: reason} <- List.last(messages),
         true <- RubyWords.again?(reason),
         %{text: text} <- Enum.find(messages, &(&1.id == id)) do
      {:noreply, say(socket, text)}
    else
      _not_the_last_failure -> {:noreply, socket}
    end
  end

  def handle_event("stop", _params, %{assigns: %{answer: %{asked: id}}} = socket) do
    with {:ok, %{} = message} <- Ruby.message(id, scope(socket)) do
      Ruby.stop_reply(message, scope(socket))
    end

    {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The reply has a row, or it ended: the page reads the conversation
  # again, and the status says the state once.
  @impl true
  def handle_info({:ruby, :reply, _id, state}, %{assigns: %{conversation: %{}}} = socket) do
    said = if state == :streaming, do: RubyWords.said(:working), else: RubyWords.said(state)
    {:noreply, socket |> read() |> assign(:said, said)}
  end

  # The whole text of the reply so far, for the answer that the page shows:
  # a late message of an earlier reply changes nothing.
  def handle_info({:ruby, :text, id, text}, %{assigns: %{answer: %{} = answer}} = socket)
      when is_binary(text) and text != "" and (is_nil(answer.id) or answer.id == id) do
    said = if answer.blocks == [], do: RubyWords.said(:writing), else: socket.assigns.said
    answer = %{answer | id: id, blocks: blocks(text, socket.assigns)}
    {:noreply, assign(socket, answer: answer, said: said)}
  end

  # A step of the reply: a call of a tool that started or ended, as code
  # made it. The references that it returned are records that a link of
  # Ruby may name.
  def handle_info(
        {:ruby, :step, id, %{"call_id" => call_id} = step},
        %{assigns: %{answer: %{} = answer}} = socket
      )
      when is_nil(answer.id) or answer.id == id do
    steps =
      if Enum.any?(answer.steps, &(&1["call_id"] == call_id)),
        do: Enum.map(answer.steps, &if(&1["call_id"] == call_id, do: step, else: &1)),
        else: answer.steps ++ [step]

    known = for %{"ref" => ref} <- step["refs"] || [], into: socket.assigns.known, do: ref

    {:noreply,
     assign(socket,
       answer: %{answer | id: id, steps: steps},
       known: known,
       said: RubyWords.said_step(step)
     )}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Ruby takes one message at a time, and no blank one. The first message
  # makes the conversation, and the page goes to its path, where `open/2`
  # takes up the topic and reads the message.
  defp say(%{assigns: %{answer: nil, conversation: nil}} = socket, text) when is_binary(text) do
    with {:ok, conversation} <-
           Ruby.start_conversation(about_attrs(socket.assigns.about), scope(socket)),
         {:ok, _message} <- said(conversation, text, socket) do
      socket
      |> assign_form("")
      |> push_patch(to: conversation_path(socket, conversation.id))
      |> push_event("ruby:newest", %{})
    else
      {:error, error} -> refused(socket, error, text)
    end
  end

  defp say(%{assigns: %{answer: nil, conversation: %{id: id}}} = socket, text)
       when is_binary(text) do
    case Ruby.say(id, text, scope(socket)) do
      {:ok, message} ->
        socket
        |> assign(messages: socket.assigns.messages ++ [message], answer: new_answer(message.id))
        |> assign(said: RubyWords.said(:working), problems: [], refused: nil)
        |> assign_form("")
        |> push_event("ruby:newest", %{})

      {:error, error} ->
        refused(socket, error, text)
    end
  end

  defp say(socket, _text), do: socket

  # A message that Ruby refused for a reason, such as the allowance, says
  # so in the place of the answer, with its way on, and its words go back
  # into the field, so that "Try again" sends them. Any other error is a
  # problem of the form.
  defp refused(socket, error, text) do
    case Ruby.refusal(error) do
      nil ->
        assign(socket, problems: Ruby.problems(error), refused: nil)

      reason ->
        socket
        |> assign(problems: [], refused: reason, allowance: allowance(socket, reason))
        |> assign_form(text)
    end
  end

  # The allowance of the month, for the words of a message past it.
  defp allowance(socket, :allowance), do: Ruby.settings(socket.assigns.organisation).allowance
  defp allowance(_socket, _reason), do: nil

  # A first message that Ruby refused, past the allowance for one, leaves
  # no empty conversation behind.
  defp said(conversation, text, socket) do
    case Ruby.say(conversation.id, text, scope(socket)) do
      {:ok, message} ->
        {:ok, message}

      {:error, error} ->
        Ruby.remove_conversation(conversation, scope(socket))
        {:error, error}
    end
  end

  # First the topic, then the messages: a change between the two is in the
  # messages, and one after them is on the topic.
  defp open(socket, conversation) do
    socket = leave(socket)
    if connected?(socket), do: Ruby.subscribe(conversation.id, scope(socket))

    socket =
      socket
      |> assign(conversation: conversation, problems: [], refused: nil)
      |> assign(:about, about(conversation.about, socket))
      |> read()

    # A page that opens while Ruby answers says so once.
    said =
      case socket.assigns.answer do
        nil -> nil
        %{blocks: []} -> RubyWords.said(:working)
        _writing -> RubyWords.said(:writing)
      end

    assign(socket, :said, said)
  end

  # The conversation as the database has it: its title, which Ruby gives
  # after the first answer, and its messages. A reply that is still
  # written is the answer below the list, with its words so far.
  defp read(%{assigns: %{conversation: %{id: id}}} = socket) do
    with {:ok, %{} = conversation} <- Ruby.conversation(id, scope(socket)),
         {:ok, messages} <- Ruby.messages(id, scope(socket)) do
      known = Ruby.refs(messages)

      {messages, answer} =
        split(messages, %{organisation: socket.assigns.organisation, known: known})

      assign(socket,
        known: known,
        conversation: conversation,
        page_title: RubyWords.title(conversation),
        messages: messages,
        answer: answer,
        closed?: Enum.any?(messages, &(&1.reason == :refused))
      )
      |> forget_refusal()
    else
      _gone -> push_navigate(socket, to: start_path(socket))
    end
  end

  # A refusal of the form is out of date once the conversation is closed:
  # the form is gone.
  defp forget_refusal(%{assigns: %{closed?: true}} = socket),
    do: assign(socket, refused: nil, problems: [])

  defp forget_refusal(socket), do: socket

  defp split(messages, assigns) do
    case List.last(messages) do
      %{source: :ruby, state: :streaming} = reply ->
        answer = %{new_answer(reply.response_to_id) | id: reply.id, steps: reply.steps || []}
        {Enum.drop(messages, -1), %{answer | blocks: blocks(reply.text, assigns)}}

      # The job has not made the reply yet.
      %{source: :user} = message ->
        {messages, new_answer(message.id)}

      _whole_reply_or_nothing ->
        {messages, nil}
    end
  end

  # A page that moves to another conversation, or to the start, leaves the
  # topic of the one before.
  defp leave(%{assigns: %{conversation: %{id: id}}} = socket) do
    if connected?(socket) do
      Ruby.unsubscribe(id)
      forget()
    end

    socket
  end

  defp leave(socket), do: socket

  # A message of the topic that the page left, which was on its way: the
  # page of the next conversation must not take its words or its records.
  # No message of the next topic is here yet, since the page listens to it
  # only after this.
  defp forget do
    receive do
      {:ruby, _kind, _reply_id, _value} -> forget()
    after
      0 -> :ok
    end
  end

  # The record that a page opened Ruby from (`?about=resident:<id>`), or
  # that a conversation is about, when the person can still read it. A
  # reference that names no record of theirs is no record: the page opens
  # as a plain start.
  defp about(ref, socket) do
    case Ruby.about(ref, scope(socket)) do
      {:ok, about} -> about
      :error -> nil
    end
  end

  defp about_attrs(nil), do: %{}
  defp about_attrs(%{ref: ref}), do: %{about: ref}

  # The things to ask that the start shows: about the record, when there
  # is one, and else about the organisation. Each needs a tool that the
  # role of the person can read.
  defp asks(user, organisation, about) do
    all = if about, do: RubyWords.asks_about(about), else: RubyWords.asks()

    all
    |> Enum.filter(fn {tool, _words} -> Ruby.reads?(user, organisation, tool) end)
    |> Enum.map(fn {_tool, words} -> words end)
    |> Enum.take(@asks)
  end

  defp recent(socket) do
    case Ruby.conversations(scope(socket)) do
      {:ok, conversations} -> Enum.take(conversations, @recent)
      _none -> []
    end
  end

  # `asked` is the message of the member that the answer is for: Stop
  # names it.
  defp new_answer(asked), do: %{id: nil, asked: asked, steps: [], blocks: []}

  # The words of Ruby, with a link only to a record of this conversation.
  defp blocks(text, %{organisation: organisation, known: known}),
    do: RubyMarkdown.blocks(text, organisation: organisation, known: known)

  defp assign_form(socket, text),
    do: assign(socket, :form, to_form(%{"text" => text}, as: :message))

  defp scope(socket),
    do: [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

  defp start_path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/ruby"

  defp conversation_path(socket, id),
    do: ~p"/o/#{socket.assigns.organisation.short_name}/ruby/#{id}"
end
