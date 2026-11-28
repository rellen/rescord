defmodule RescordWeb.RubyChatComponents do
  @moduledoc """
  The parts of the page of a conversation with Ruby (ADR 0069 and
  ADR 0037): the start of a new conversation, a message, the answer that
  is on its way, and the form of the message. Each is a function
  component, with no class; the look is the section of Ruby in
  `components.css`.

  The words of Ruby are HTML that `RescordWeb.RubyMarkdown` made safe. No
  part draws from the result of a tool, and none gets one.
  """

  use RescordWeb, :html

  alias RescordWeb.{RubyMarkdown, RubyWords}

  @doc """
  The start of a new conversation: what Ruby is for, who can read what
  the person asks, the things to ask, each a button that sends its words,
  and the last conversations of the person.
  """
  attr :organisation, :map, required: true
  attr :asks, :list, required: true, doc: "the words of each thing to ask"
  attr :recent, :list, required: true, doc: "the last conversations of the person"

  def start(assigns) do
    ~H"""
    <section id="ruby-start" data-start aria-label="A new conversation">
      <p>
        Ask about the residents, the tasks and the supplies of {@organisation.name}. Ruby reads
        the records that you can read, and no other.
      </p>
      <p>The administrators of {@organisation.name} can read what you ask Ruby.</p>
      <p>
        <small>Ruby is a computer program, and it can be wrong. It gives no veterinary advice.</small>
      </p>

      <h2 :if={@asks != []} id="ruby-asks-title">Things to ask</h2>
      <ul :if={@asks != []} data-suggestions aria-labelledby="ruby-asks-title">
        <li :for={{words, index} <- Enum.with_index(@asks)} id={"ruby-ask-#{index}"}>
          <button type="button" phx-click="ask" phx-value-text={words}>{words}</button>
        </li>
      </ul>

      <h2 :if={@recent != []} id="ruby-recent-title">Your last conversations</h2>
      <ul :if={@recent != []} data-links aria-labelledby="ruby-recent-title">
        <li :for={conversation <- @recent}>
          <.link navigate={conversation_path(@organisation, conversation)}>
            <span>
              {RubyWords.title(conversation)}
              <small>{RubyWords.moment(conversation.last_message_at, @organisation)}</small>
            </span>
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  # A link to a conversation opens it at its newest message: the browser
  # scrolls to the element of the fragment.
  defp conversation_path(organisation, conversation),
    do: ~p"/o/#{organisation.short_name}/ruby/#{conversation.id}" <> "#newest"

  @doc """
  One message of the conversation, as an `<article>` with a heading: what
  the member said, as plain text, or a reply of Ruby, as Markdown.
  """
  attr :message, :map, required: true
  attr :organisation, :map, required: true

  def message(%{message: %{source: :user}} = assigns) do
    ~H"""
    <article data-from="member" aria-labelledby={"who-#{@message.id}"}>
      <header>
        <h2 id={"who-#{@message.id}"}>You said</h2>
        <.at time={@message.inserted_at} organisation={@organisation} />
      </header>
      <p>{@message.text}</p>
    </article>
    """
  end

  def message(%{message: %{source: :ruby}} = assigns) do
    ~H"""
    <article data-from="ruby" aria-labelledby={"who-#{@message.id}"}>
      <header>
        <h2 id={"who-#{@message.id}"}><.icon name="gem" /> Ruby</h2>
        <.at time={@message.inserted_at} organisation={@organisation} />
      </header>

      <.prose text={@message.text} />

      <p :if={@message.state == :stopped}>
        <small>You stopped this answer. Ruby recorded nothing.</small>
      </p>
      <p :if={@message.state == :failed} role="alert">{RubyWords.problem(@message.reason)}</p>
    </article>
    """
  end

  attr :time, DateTime, required: true
  attr :organisation, :map, required: true

  defp at(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@time)}>{RubyWords.moment(@time, @organisation)}</time>
    """
  end

  @doc "Words of Ruby that are whole: Markdown, as HTML that `RubyMarkdown` made safe."
  attr :text, :string, required: true

  def prose(assigns) do
    assigns = assign(assigns, :blocks, RubyMarkdown.blocks(assigns.text))

    ~H"""
    <div :if={@blocks != []} data-prose>
      <%!-- The words are HTML that RubyMarkdown made safe. --%>
      <div :for={html <- @blocks} data-block>{Phoenix.HTML.raw(html)}</div>
    </div>
    """
  end

  @doc """
  The answer that is on its way: "is working" until the first words, and
  then the words as they arrive, one block of Markdown each, with a key,
  so that LiveView sends only the block that changed.
  """
  attr :answer, :map, required: true, doc: "with `blocks`, the safe HTML of the words so far"

  def answer(assigns) do
    ~H"""
    <article id="ruby-answer" data-from="ruby" aria-labelledby="ruby-answer-who">
      <header>
        <h2 id="ruby-answer-who"><.icon name="gem" /> Ruby</h2>
        <small :if={@answer.blocks == []}><.icon name="arrow-path" spin /> is working</small>
        <small :if={@answer.blocks != []}>is writing</small>
      </header>

      <div :if={@answer.blocks != []} data-prose aria-busy="true">
        <%!-- The words are HTML that RubyMarkdown made safe. --%>
        <div :for={{html, index} <- Enum.with_index(@answer.blocks)} :key={index} data-block>
          {Phoenix.HTML.raw(html)}
        </div>
      </div>
    </article>
    """
  end

  @doc """
  The form of the message, at the foot of the screen. While Ruby answers,
  the member can type the next message and cannot send it: the button is
  Stop. The page shows the line on the connection while it has none.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :answering?, :boolean, required: true

  def composer(assigns) do
    ~H"""
    <.form
      for={@form}
      id="ruby-say"
      data-composer
      aria-label="Message to Ruby"
      phx-change="draft"
      phx-submit="send"
    >
      <p id="ruby-offline" role="alert" hidden>
        No connection. Your message stays here until Rescord is back.
      </p>
      <label for="ruby-message">Message to Ruby</label>
      <textarea
        id="ruby-message"
        name={@form[:text].name}
        rows="1"
        maxlength="4000"
        autocomplete="off"
        placeholder="Ask Ruby"
        phx-debounce="300"
      >{Phoenix.HTML.Form.normalize_value("textarea", @form[:text].value)}</textarea>
      <footer>
        <button :if={!@answering?} id="ruby-send" type="submit" phx-disable-with="Sending">
          <.icon name="arrow-up" /> Send
        </button>
        <button :if={@answering?} id="ruby-stop" type="button" phx-click="stop">
          <.icon name="stop" /> Stop
        </button>
      </footer>
    </.form>
    """
  end
end
