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
      <p>
        The administrators of {@organisation.name}, whose role can change its settings,
        can read what you ask Ruby.
      </p>
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
      <p :if={@recent != []}>
        <.link navigate={~p"/o/#{@organisation.short_name}/ruby/conversations"} id="ruby-all">
          All your conversations
        </.link>
      </p>
    </section>
    """
  end

  @doc """
  The record that a conversation is about, as a link back to its page:
  "About Biscuit". The page shows it at the start and above the messages.
  """
  attr :about, :map, required: true, doc: "`%{ref, kind, label}`, from `Rescord.Ruby.about/2`"
  attr :organisation, :map, required: true

  def about(assigns) do
    ~H"""
    <.link id="ruby-about" navigate={RubyMarkdown.path(@about.ref, @organisation)} data-about>
      <span :if={@about.kind == "resident" and @about.name} data-portrait aria-hidden="true">
        <span>{String.first(@about.name)}</span>
      </span>
      <span><small>About</small> {@about.label}</span>
    </.link>
    """
  end

  @doc """
  What a person changes of a conversation, each closed in a `<details>`:
  its name, and its removal, which says that nothing brings it back.
  """
  attr :name_form, :any, required: true

  def manage(assigns) do
    ~H"""
    <div id="ruby-manage" data-manage>
      <details id="ruby-rename" open={@name_form.errors != []}>
        <summary>Change the name</summary>
        <.form for={@name_form} id="ruby-name" phx-submit="rename">
          <.input field={@name_form[:title]} type="text" label="Name of the conversation" />
          <footer><button type="submit">Save the name</button></footer>
        </.form>
      </details>
      <.confirm id="ruby-remove" summary="Remove this conversation">
        <p>
          Rescord deletes this conversation for real, with its messages. Nobody can bring it
          back.
        </p>
        <.button type="button" variant="danger" phx-click="remove">
          Remove this conversation
        </.button>
      </.confirm>
    </div>
    """
  end

  # A link to a conversation opens it at its newest message: the browser
  # scrolls to the element of the fragment.
  defp conversation_path(organisation, conversation),
    do: ~p"/o/#{organisation.short_name}/ruby/#{conversation.id}" <> "#newest"

  @doc """
  One message of the conversation, as an `<article>` with a heading: what
  the member said, as plain text, or a reply of Ruby, as Markdown, with
  the records that it links to and the steps that it took.
  """
  attr :message, :map, required: true
  attr :organisation, :map, required: true

  attr :known, :any,
    default: [],
    doc: "the references that a tool returned in this conversation"

  attr :way_on?, :boolean,
    default: false,
    doc: "the last reply, with no answer on its way: a problem shows its way on"

  attr :settings?, :boolean, default: false, doc: "the person can change the settings of Ruby"

  attr :rate_problems, :list,
    default: [],
    doc: "the refusals of the last press of \"Was this answer right?\" of this answer"

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

      <.prose
        :if={RubyWords.keeps_words?(@message.reason)}
        text={@message.text}
        organisation={@organisation}
        known={@known}
      />

      <p :if={@message.state == :stopped}>
        <small>You stopped this answer. Ruby recorded nothing.</small>
      </p>
      <.problem
        :if={@message.reason}
        reason={@message.reason}
        organisation={@organisation}
        way_on?={@way_on?}
        settings?={@settings?}
        again={{:message, @message.response_to_id}}
      />

      <.records
        :if={@message.state == :complete}
        id={"records-#{@message.id}"}
        records={records(@message, @organisation, @known)}
        organisation={@organisation}
      />
      <.steps_done id={"steps-#{@message.id}"} steps={@message.steps || []} />
      <.rate :if={@message.state == :complete} message={@message} problems={@rate_problems} />
    </article>
    """
  end

  @doc """
  "Was this answer right?" at the foot of a whole answer: "Yes" and "No",
  pressed at once, as words and with `aria-pressed`. After "No", what was
  wrong, which nobody must write, and a box, not ticked, that sends this
  one question, its answer and what Ruby read for it to the
  administrators. A refusal of the last press shows below the buttons.
  """
  attr :message, :map, required: true
  attr :problems, :list, default: [], doc: "the refusals of the last press, as sentences"

  def rate(assigns) do
    assigns =
      assign(assigns,
        report:
          to_form(
            %{
              "rating_note" => assigns.message.rating_note || "",
              "send" => assigns.message.reported_at != nil
            },
            as: :report,
            id: "report-#{assigns.message.id}"
          )
      )

    ~H"""
    <div id={"rate-#{@message.id}"} data-rating>
      <div role="group" data-rate aria-labelledby={"rate-words-#{@message.id}"}>
        <span id={"rate-words-#{@message.id}"}>Was this answer right?</span>
        <button
          :for={{rating, word} <- [up: "Yes", down: "No"]}
          type="button"
          aria-pressed={to_string(@message.rating == rating)}
          phx-click="rate"
          phx-value-reply={@message.id}
          phx-value-rating={rating}
        >
          {word}
        </button>
      </div>
      <.problems :if={@problems != []} list={@problems} />
      <.form
        :if={@message.rating == :down}
        for={@report}
        id={"report-#{@message.id}"}
        phx-submit="report"
      >
        <input type="hidden" name="report[reply]" value={@message.id} />
        <.input
          field={@report[:rating_note]}
          type="textarea"
          label="What was wrong?"
          hint="You need not write anything. At most 500 characters."
          maxlength="500"
        />
        <.input
          field={@report[:send]}
          type="checkbox"
          label="Send this question and its answer, and what Ruby read for it, to the administrators"
          hint="They can read each conversation already. This asks them to look at this answer."
        />
        <button type="submit">Save what was wrong</button>
      </.form>
      <p :if={@message.rating == :down and @message.reported_at}>
        <.icon name="check" /> You sent this answer to the administrators.
      </p>
    </div>
    """
  end

  # The records that a tool of this reply returned and that a link of its
  # words goes to, as the page shows the words.
  defp records(%{text: text, steps: steps}, organisation, known) when is_binary(text) do
    linked = RubyMarkdown.paths(text, organisation: organisation, known: known)

    for %{"refs" => refs} <- steps || [],
        %{"ref" => ref} = record <- refs,
        path = RubyMarkdown.path(ref, organisation),
        MapSet.member?(linked, path),
        uniq: true,
        do: Map.put(record, "path", path)
  end

  defp records(_message, _organisation, _known), do: []

  @doc """
  What went wrong, in the place of the answer, and the way on: a reply
  that ended with a reason, or a message that Ruby refused. A reply that
  was cut is no failure: its words are there, and the line says so.
  """
  attr :reason, :atom, required: true
  attr :organisation, :map, required: true
  attr :way_on?, :boolean, default: true
  attr :settings?, :boolean, default: false

  attr :again, :any,
    required: true,
    doc: "what \"Try again\" sends: `{:message, id}`, the message of the member, or `:form`"

  attr :allowance, :any,
    default: :unknown,
    doc:
      "the allowance of the organisation in cents, for a message past it, when the page read it"

  def problem(assigns) do
    assigns =
      assign(assigns,
        way: assigns.way_on? && RubyWords.way_on(assigns.reason),
        words: RubyWords.problem(assigns.reason, assigns.organisation, words_options(assigns))
      )

    ~H"""
    <p :if={@reason == :cut}>{@words}</p>
    <p :if={@reason != :cut} role="alert">{@words}</p>
    <p :if={@way in [:again, :rest, :new] or (@way == :settings and @settings?)} data-way-on>
      <button
        :if={@way == :again and match?({:message, _id}, @again)}
        type="button"
        phx-click="again"
        phx-value-id={elem(@again, 1)}
      >
        <.icon name="arrow-path" /> Try again
      </button>
      <button :if={@way == :again and @again == :form} type="submit" form="ruby-say">
        <.icon name="arrow-path" /> Try again
      </button>
      <button :if={@way == :rest} type="button" phx-click="ask" phx-value-text={RubyWords.rest()}>
        Ask for the rest
      </button>
      <.link :if={@way == :new} patch={~p"/o/#{@organisation.short_name}/ruby"}>
        <.icon name="plus" /> New conversation
      </.link>
      <.link :if={@way == :settings} navigate={~p"/o/#{@organisation.short_name}/settings/ruby"}>
        The settings of Ruby
      </.link>
    </p>
    """
  end

  defp words_options(%{allowance: :unknown}), do: []
  defp words_options(%{allowance: allowance}), do: [allowance: allowance]

  attr :time, DateTime, required: true
  attr :organisation, :map, required: true

  defp at(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@time)}>{RubyWords.moment(@time, @organisation)}</time>
    """
  end

  @doc "Words of Ruby that are whole: Markdown, as HTML that `RubyMarkdown` made safe."
  attr :text, :string, required: true
  attr :organisation, :map, required: true
  attr :known, :any, default: []

  def prose(assigns) do
    assigns =
      assign(
        assigns,
        :blocks,
        RubyMarkdown.blocks(assigns.text,
          organisation: assigns.organisation,
          known: assigns.known
        )
      )

    ~H"""
    <div :if={@blocks != []} data-prose>
      <%!-- The words are HTML that RubyMarkdown made safe. --%>
      <div :for={html <- @blocks} data-block>{Phoenix.HTML.raw(html)}</div>
    </div>
    """
  end

  @doc """
  The records that an answer comes from, each a card that goes to its
  page: six, and the others in a `<details>`.
  """
  attr :id, :string, required: true
  attr :records, :list, required: true, doc: "each with `ref`, `label`, `path` and maybe `detail`"
  attr :organisation, :map, required: true

  def records(assigns) do
    {shown, more} = Enum.split(assigns.records, 6)
    assigns = assign(assigns, shown: shown, more: more)

    ~H"""
    <footer :if={@records != []}>
      <h3>From the records</h3>
      <ul data-links>
        <li :for={record <- @shown}><.record record={record} /></li>
      </ul>
      <details :if={@more != []} id={"#{@id}-more"}>
        <summary>and {length(@more)} more</summary>
        <ul data-links>
          <li :for={record <- @more}><.record record={record} /></li>
        </ul>
      </details>
    </footer>
    """
  end

  attr :record, :map, required: true

  defp record(assigns) do
    ~H"""
    <.link navigate={@record["path"]}>
      <span :if={String.starts_with?(@record["ref"], "resident:")} data-portrait>
        <span>{String.first(@record["label"])}</span>
      </span>
      <span>{@record["label"]} <small :if={@record["detail"]}>{@record["detail"]}</small></span>
    </.link>
    """
  end

  @doc "The steps of a reply, closed in a `<details>`: \"What Ruby read: 2 steps\"."
  attr :id, :string, required: true
  attr :steps, :list, required: true

  def steps_done(assigns) do
    ~H"""
    <details :if={@steps != []} id={@id}>
      <summary>{RubyWords.steps_summary(@steps)}</summary>
      <.steps steps={@steps} />
    </details>
    """
  end

  attr :steps, :list, required: true
  attr :rest, :global

  defp steps(assigns) do
    ~H"""
    <ul data-steps {@rest}>
      <li :for={step <- @steps} :key={step["call_id"]} data-step={step["state"]}>
        <.icon :if={step["state"] == "running"} name="arrow-path" spin />
        <.icon :if={step["state"] == "done"} name="check" />
        <.icon :if={step["state"] == "failed"} name="exclamation-triangle" />
        <.icon :if={step["state"] == "stopped"} name="stop" />
        {RubyWords.step(step)}
        <small :if={RubyWords.outcome(step)}>{RubyWords.outcome(step)}</small>
      </li>
    </ul>
    """
  end

  @doc """
  The answer that is on its way: its steps while Ruby reads, and then the
  words as they arrive, one block of Markdown each, with a key, so that
  LiveView sends only the block that changed; the steps fold then.
  """
  attr :answer, :map,
    required: true,
    doc: "with `id`, `steps` and `blocks`, the safe HTML of the words so far"

  def answer(assigns) do
    ~H"""
    <article id="ruby-answer" data-from="ruby" aria-labelledby="ruby-answer-who">
      <header>
        <h2 id="ruby-answer-who"><.icon name="gem" /> Ruby</h2>
        <small :if={@answer.blocks == []}><.icon name="arrow-path" spin /> is working</small>
        <small :if={@answer.blocks != []}>is writing</small>
      </header>

      <.steps
        :if={@answer.blocks == [] and @answer.steps != []}
        steps={@answer.steps}
        aria-label="What Ruby does"
      />

      <div :if={@answer.blocks != []} data-prose aria-busy="true">
        <%!-- The words are HTML that RubyMarkdown made safe. --%>
        <div :for={{html, index} <- Enum.with_index(@answer.blocks)} :key={index} data-block>
          {Phoenix.HTML.raw(html)}
        </div>
      </div>

      <.steps_done
        :if={@answer.blocks != []}
        id={"steps-#{@answer.id || "answer"}"}
        steps={@answer.steps}
      />
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
  attr :closed?, :boolean, default: false, doc: "the conversation takes no more messages"
  attr :organisation, :map, required: true

  def composer(%{closed?: true} = assigns) do
    ~H"""
    <section id="ruby-closed" data-composer aria-labelledby="ruby-closed-words">
      <p id="ruby-closed-words">This conversation is closed.</p>
      <.link patch={~p"/o/#{@organisation.short_name}/ruby"} data-variant="primary">
        <.icon name="plus" /> New conversation
      </.link>
    </section>
    """
  end

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
