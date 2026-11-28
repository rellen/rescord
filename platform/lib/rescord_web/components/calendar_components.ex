defmodule RescordWeb.CalendarComponents do
  @moduledoc """
  The parts of the page of the calendar feeds (ADR 0074 and ADR 0037): the
  form of a new feed, the address of a feed that was made a moment ago, the
  feeds of the person, the feeds of the other members, and how a person
  subscribes in a calendar app.

  Each part is a function component: the page holds the state.
  """

  use RescordWeb, :html

  alias Rescord.Accounts
  alias RescordWeb.CalendarWords

  @doc """
  The address of a feed, one time: the page shows it only after the person
  made the feed, because Rescord stores no address. A person copies it into
  their calendar app.
  """
  attr :name, :string, required: true, doc: "the name of the feed"
  attr :address, :string, required: true

  def new_address(assigns) do
    ~H"""
    <section id="new-address" aria-labelledby="new-address-heading">
      <h2 id="new-address-heading">The address of {@name}</h2>
      <p role="status">
        The feed is ready. Copy its address now: this page shows it this one time.
      </p>
      <.input
        id="feed-address"
        name="address"
        type="url"
        label="Address of the calendar"
        value={@address}
        readonly
        autocomplete="off"
        spellcheck="false"
      />
      <p>
        <button type="button" data-copy="feed-address" data-copied="feed-address-copied">
          Copy the address
        </button>
        <span id="feed-address-copied" role="status"></span>
      </p>
      <p>
        Give the address to your calendar app, and to nobody. Each person who has it reads
        the feed.
      </p>
    </section>
    """
  end

  @doc "The form that makes a feed: its name and its parts."
  attr :form, :any, required: true
  attr :problems, :list, required: true
  attr :limit, :integer, required: true, doc: "the most feeds that one member has"

  def new_feed(assigns) do
    ~H"""
    <section aria-labelledby="new-feed-heading">
      <h2 id="new-feed-heading">Make a feed</h2>
      <.problems list={@problems} />
      <.form for={@form} id="new-feed" phx-submit="subscribe">
        <.input
          field={@form[:name]}
          label="Name, as your calendar app shows it"
          maxlength="60"
          required
        />
        <.input
          field={@form[:tasks]}
          type="select"
          label="Tasks"
          options={CalendarWords.tasks_options()}
        />
        <fieldset>
          <legend>Dates</legend>
          <.input
            field={@form[:with_returns]}
            type="checkbox"
            label="The days that residents are expected back"
          />
          <.input
            field={@form[:with_expiry]}
            type="checkbox"
            label="The expiry dates of the stock"
          />
        </fieldset>
        <fieldset>
          <legend>Notes</legend>
          <.input
            field={@form[:with_notes]}
            type="checkbox"
            label="Include the notes that people wrote"
          />
          <p>
            <small>
              A calendar service keeps a copy of the feed. Without this, an event has the
              title, the names of the residents and a link to Rescord, and no note.
            </small>
          </p>
        </fieldset>
        <footer>
          <.button type="submit">Make the feed</.button>
        </footer>
      </.form>
      <p><small>You can have {@limit} feeds.</small></p>
    </section>
    """
  end

  @doc "The feeds of the person, each with a button that revokes it."
  attr :feeds, :list, required: true
  attr :organisation, :any, required: true

  def own_feeds(assigns) do
    ~H"""
    <section aria-labelledby="own-feeds-heading">
      <h2 id="own-feeds-heading">Your feeds</h2>
      <p :if={@feeds == []} id="no-feeds">You have no feed.</p>
      <ul :if={@feeds != []} id="own-feeds">
        <li :for={feed <- @feeds} id={"feed-#{feed.id}"}>
          <.feed_words feed={feed} organisation={@organisation} />
          <button
            type="button"
            phx-click="revoke"
            phx-value-id={feed.id}
            data-confirm={"Revoke the feed #{feed.name}? The calendar app that reads it gets nothing more."}
            aria-label={"Revoke the feed #{feed.name}"}
          >
            Revoke
          </button>
        </li>
      </ul>
    </section>
    """
  end

  @doc """
  The feeds of the other members, for a person who invites and removes the
  members. That person revokes a feed, and reads no address.
  """
  attr :feeds, :list, required: true
  attr :organisation, :any, required: true

  def other_feeds(assigns) do
    ~H"""
    <section aria-labelledby="other-feeds-heading">
      <h2 id="other-feeds-heading">The feeds of the other members</h2>
      <p :if={@feeds == []} id="no-other-feeds">No other member has a feed.</p>
      <ul :if={@feeds != []} id="other-feeds">
        <li :for={feed <- @feeds} id={"feed-#{feed.id}"}>
          <.feed_words feed={feed} organisation={@organisation} owner={feed.member.email} />
          <button
            type="button"
            phx-click="revoke"
            phx-value-id={feed.id}
            data-confirm={"Revoke the feed #{feed.name} of #{feed.member.email}?"}
            aria-label={"Revoke the feed #{feed.name} of #{feed.member.email}"}
          >
            Revoke
          </button>
        </li>
      </ul>
    </section>
    """
  end

  attr :feed, :any, required: true
  attr :organisation, :any, required: true
  attr :owner, :any, default: nil

  # What a row says of a feed: its name, its owner, its parts, and when a
  # calendar app last read it.
  defp feed_words(assigns) do
    ~H"""
    <span>
      <strong>{@feed.name}</strong>
      <small :if={@owner}>{@owner}</small>
      <small>{Enum.join(CalendarWords.parts(@feed), ". ")}.</small>
      <small>{CalendarWords.last_read(local(@organisation, @feed.last_fetched_at))}.</small>
    </span>
    """
  end

  defp local(_organisation, nil), do: nil
  defp local(organisation, %DateTime{} = at), do: Accounts.local_time(organisation, at)

  @doc "How a person subscribes to a feed in the common calendar apps."
  def how_to(assigns) do
    ~H"""
    <section aria-labelledby="how-to-heading">
      <h2 id="how-to-heading">How to subscribe</h2>
      <p>
        A calendar app subscribes to a calendar by its address. Look for words such as
        "Add a calendar from a URL", "Subscribe to a calendar" or "Add subscription
        calendar", and give the app the address of the feed.
      </p>
      <ul>
        <li>
          Google Calendar: on a computer, at "Other calendars", choose "From URL". The
          calendar then shows on your phone too.
        </li>
        <li>Apple Calendar: add a calendar, and choose a subscription calendar.</li>
        <li>Outlook: add a calendar, and choose "Subscribe from web".</li>
      </ul>
      <p>
        The app reads the feed again on its own schedule. Some apps take many hours, so a
        new task can be late in your calendar. Rescord itself always shows the tasks as
        they are now.
      </p>
      <p>
        An event links to its record in Rescord. Complete a task there: a change in your
        calendar app changes nothing in Rescord.
      </p>
    </section>
    """
  end
end
