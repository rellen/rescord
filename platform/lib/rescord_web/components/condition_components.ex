defmodule RescordWeb.ConditionComponents do
  @moduledoc """
  The parts that show the conditions of a resident (ADR 0083 and ADR 0037):
  the state of a condition, the conditions of a resident as a list and as
  the choices of its journal, the card of one condition with what a member
  can do with it, and a list of counts with a bar in each row.

  A condition here is an episode of `Rescord.Journal`, with its condition
  and the label of it.
  """

  use RescordWeb, :html

  alias RescordWeb.{JournalWords, ResidentWords}

  @doc "The address of the journal of a resident, with the parameters of its filters."
  def journal_path(organisation, resident_id, params \\ []) do
    params = Enum.reject(params, fn {_key, value} -> is_nil(value) end)
    ~p"/o/#{organisation.short_name}/residents/#{resident_id}/journal?#{params}"
  end

  @doc "The state of a condition: ongoing, chronic or resolved."
  attr :episode, :any, required: true

  def condition_state(assigns) do
    {kind, word} = JournalWords.condition_state(assigns.episode)
    assigns = assign(assigns, kind: kind, word: word)

    ~H"""
    <.state kind={@kind}>{@word}</.state>
    """
  end

  @doc """
  The conditions of a resident as a list: each with its state, and one line
  with its days, its note and the number of its entries. The name is a link
  to the entries about it.
  """
  attr :episodes, :list, required: true
  attr :organisation, :any, required: true
  attr :today, :any, required: true
  attr :rest, :global

  def condition_list(assigns) do
    ~H"""
    <ul data-conditions {@rest}>
      <li :for={episode <- @episodes} id={"condition-#{episode.id}"}>
        <.link navigate={journal_path(@organisation, episode.resident_id, episode: episode.id)}>
          {episode.condition.label}
        </.link>
        <.condition_state episode={episode} />
        <small>{line(episode, @today)}</small>
      </li>
    </ul>
    """
  end

  # `Since 3 November 2026, 25 days · left hind foot · 4 entries`.
  defp line(episode, today) do
    [
      JournalWords.condition_days(episode, today),
      episode.note,
      JournalWords.count(episode.entry_count, "entry")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc """
  The conditions of a resident as the choices of its journal: a link for
  each entry, and one for each condition. The one that the page shows is
  marked.
  """
  attr :episodes, :list, required: true
  attr :current, :any, required: true, doc: "the condition that the page shows, or nil"
  attr :only, :any, required: true
  attr :organisation, :any, required: true
  attr :resident, :any, required: true

  def condition_nav(assigns) do
    ~H"""
    <nav :if={@episodes != []} aria-label="Conditions">
      <ul>
        <li>
          <.link
            patch={journal_path(@organisation, @resident.id, only: @only)}
            aria-current={is_nil(@current) && "true"}
          >
            Each entry
          </.link>
        </li>
        <li :for={episode <- @episodes}>
          <.link
            patch={journal_path(@organisation, @resident.id, only: @only, episode: episode.id)}
            aria-current={@current && @current.id == episode.id && "true"}
          >
            {choice(episode)}
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  # A resolved condition says its last day: a resident can have had one
  # condition two times.
  defp choice(%{ended_on: nil} = episode), do: to_string(episode.condition.label)

  defp choice(episode),
    do: "#{episode.condition.label}, to #{ResidentWords.date(episode.ended_on)}"

  @doc """
  The section of the conditions on the page of a resident: what it has now,
  what it had in a closed part, and the links to record a diagnosis and to
  the conditions of each resident.
  """
  attr :episodes, :list, required: true
  attr :organisation, :any, required: true
  attr :resident, :any, required: true
  attr :today, :any, required: true
  attr :can_write?, :boolean, required: true

  def resident_conditions(assigns) do
    {ongoing, earlier} = Enum.split_with(assigns.episodes, &is_nil(&1.ended_on))
    assigns = assign(assigns, ongoing: ongoing, earlier: earlier)

    ~H"""
    <section aria-labelledby="conditions-heading">
      <h2 id="conditions-heading">Conditions</h2>
      <p :if={@ongoing == []}>No condition is recorded now.</p>
      <.condition_list
        :if={@ongoing != []}
        id="conditions-now"
        episodes={@ongoing}
        organisation={@organisation}
        today={@today}
      />
      <details :if={@earlier != []} id="conditions-earlier">
        <summary>{JournalWords.count(length(@earlier), "earlier condition")}</summary>
        <.condition_list episodes={@earlier} organisation={@organisation} today={@today} />
      </details>
      <p>
        <.link
          :if={@can_write?}
          navigate={journal_path(@organisation, @resident.id, kind: "diagnosis")}
          data-variant="secondary"
        >
          Record a diagnosis
        </.link>
        <.link
          navigate={~p"/o/#{@organisation.short_name}/residents/conditions"}
          data-variant="secondary"
        >
          Conditions of each resident
        </.link>
      </p>
    </section>
    """
  end

  @doc """
  The card of one condition of a resident, with what the person can do with
  it: mark it as resolved, open it again, change it, and remove it.
  """
  attr :episode, :any, required: true
  attr :today, :any, required: true
  attr :can, :map, required: true, doc: "whether the role can resolve, reopen, revise and remove"

  def condition_card(assigns) do
    ~H"""
    <article data-condition id="condition">
      <header>
        <h2>{@episode.condition.label}</h2>
        <.condition_state episode={@episode} />
      </header>
      <.list>
        <:item title="Started">{ResidentWords.date(@episode.started_on)}</:item>
        <:item :if={@episode.ended_on} title="Last day">
          {ResidentWords.date(@episode.ended_on)}
        </:item>
        <:item title="How long">{how_long(@episode, @today)}</:item>
        <:item title="Chronic">{if @episode.chronic, do: "Yes", else: "No"}</:item>
        <:item :if={@episode.note} title="Note">{@episode.note}</:item>
      </.list>

      <details :if={@can.resolve and is_nil(@episode.ended_on)} id="resolve-details">
        <summary>Mark as resolved</summary>
        <form id="resolve" phx-submit="resolve_episode">
          <.input
            id="resolve-ended-on"
            name="episode[ended_on]"
            type="date"
            label="Last day"
            value={Date.to_iso8601(@today)}
            min={Date.to_iso8601(@episode.started_on)}
            max={Date.to_iso8601(@today)}
            required
          />
          <footer><.button type="submit">Mark as resolved</.button></footer>
        </form>
      </details>

      <details :if={@can.reopen and @episode.ended_on} id="reopen-details">
        <summary>Open again</summary>
        <p>Open a condition again when it was not over. A condition that came back is a new one:
          record a diagnosis.</p>
        <.button phx-click="reopen_episode">Open the condition again</.button>
      </details>

      <details :if={@can.revise} id="revise-details">
        <summary>Change this condition</summary>
        <form id="revise" phx-submit="revise_episode">
          <.input
            id="revise-started-on"
            name="episode[started_on]"
            type="date"
            label="First day"
            value={Date.to_iso8601(@episode.started_on)}
            max={Date.to_iso8601(@today)}
            required
          />
          <.input
            :if={@episode.ended_on}
            id="revise-ended-on"
            name="episode[ended_on]"
            type="date"
            label="Last day"
            value={Date.to_iso8601(@episode.ended_on)}
            max={Date.to_iso8601(@today)}
            required
          />
          <.input
            id="revise-chronic"
            name="episode[chronic]"
            type="checkbox"
            label="Chronic: the resident keeps this condition"
            checked={@episode.chronic}
          />
          <.input
            id="revise-note"
            name="episode[note]"
            type="text"
            label="Note, such as the foot or the eye"
            value={@episode.note}
            maxlength="200"
          />
          <footer><.button type="submit">Save the change</.button></footer>
        </form>
      </details>

      <details :if={@can.remove} id="remove-condition-details">
        <summary>Remove this condition</summary>
        <p>
          Remove a condition only when somebody recorded it by mistake. Its entries stay in the
          journal, about no condition. For a condition that is over, mark it as resolved.
        </p>
        <.button phx-click="remove_episode">Remove the condition</.button>
      </details>
    </article>
    """
  end

  defp how_long(%{ended_on: nil, started_on: from}, today) do
    case Date.diff(today, from) do
      0 -> "Since today"
      days -> "#{JournalWords.count(days, "day")}, and not over"
    end
  end

  defp how_long(%{started_on: from, ended_on: to}, _today),
    do: JournalWords.count(Date.diff(to, from) + 1, "day")

  @doc """
  A list of counts: each row has a name, a number and a bar as long as the
  number, against the largest number of the list. The bar is a drawing that
  a screen reader does not read: the number says it.

  A row is `%{label: words, count: number}`, with `to:` for a name that is
  a link.
  """
  attr :rows, :list, required: true
  attr :rest, :global

  def counts(assigns) do
    assigns = assign(assigns, most: assigns.rows |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end))

    ~H"""
    <ul data-counts {@rest}>
      <li :for={row <- @rows}>
        <.link :if={row[:to]} navigate={row.to}>{row.label}</.link>
        <span :if={!row[:to]}>{row.label}</span>
        <data value={row.count}>{JournalWords.number(row.count)}</data>
        <svg
          data-bar
          viewBox="0 0 100 4"
          preserveAspectRatio="none"
          aria-hidden="true"
          focusable="false"
        >
          <rect width={share(row.count, @most)} height="4" fill="currentColor" />
        </svg>
      </li>
    </ul>
    """
  end

  @doc """
  The length of a bar for a number, from 0 to 100, against the largest
  number of its list.

      iex> RescordWeb.ConditionComponents.share(3, 4)
      75

      iex> RescordWeb.ConditionComponents.share(0, 0)
      0
  """
  def share(_count, 0), do: 0
  def share(count, most), do: round(count * 100 / most)
end
