defmodule RescordWeb.AttentionComponents do
  @moduledoc """
  The parts of the first page of an organisation (ADR 0065 and ADR 0037):
  what needs somebody now, as `Rescord.Attention.parts/2` gives it.

  Each part of the organisation with something in it is a section with a
  list. A row is the name of a record, which is the link to the page where
  a person acts on it, then its state, then a few facts. The page of the
  record does the work: a row has no button.
  """

  use RescordWeb, :html

  alias Rescord.{Accounts, Attention, Tasks, Transfers}

  alias RescordWeb.{
    InventoryWords,
    LocationComponents,
    ResidentWords,
    TaskComponents,
    TaskWords,
    TransferWords
  }

  # The title of each part, and the words of the link to its page.
  @parts [
    tasks: {"Tasks", "All the tasks of today"},
    inventory: {"Stock", "The whole inventory"},
    residents: {"Residents", "All the residents"},
    housing: {"Housing", "The whole housing"},
    transfers: {"Transfers and partners", "All the transfers"}
  ]

  @doc "The parts that have words, for the test that holds them."
  def parts, do: Keyword.keys(@parts)

  @doc """
  What needs somebody now: a line that says how much, and a section for
  each part with something in it. With nothing, it says so, and says what
  the page looks for.
  """
  attr :parts, :list, required: true, doc: "the parts of `Rescord.Attention.parts/2`"
  attr :organisation, :map, required: true
  attr :now, :any, required: true, doc: "the instant of the read"
  attr :members, :list, required: true, doc: "each member as `{email, user id}`"
  attr :user, :map, required: true

  def attention(assigns) do
    assigns = assign(assigns, total: Attention.total(assigns.parts))

    ~H"""
    <section aria-labelledby="attention-heading" id="attention">
      <h2 id="attention-heading">Needs attention</h2>

      <%!-- A screen reader says the line again when the number changes. --%>
      <p role="status" id="attention-summary">
        <.state :if={@total == 0} kind="ok">Nothing needs attention now</.state>
        <span :if={@total > 0}>{summary(@total)}</span>
      </p>

      <p :if={@total == 0} id="attention-nothing">
        A task that is overdue or due today, an item to count or to order, a resident that is
        expected or late back, a location over its capacity, and a transfer that waits for an
        answer are here when your role can act on them. The page shows a change at once, and
        reads them again each minute.
      </p>

      <section
        :for={part <- @parts}
        id={"attention-#{part.part}"}
        aria-labelledby={"attention-#{part.part}-heading"}
      >
        <h3 id={"attention-#{part.part}-heading"}>
          <.icon name={RescordWeb.Icons.section(part.part)} /> {title(part.part)}
          <small>{part.total}</small>
        </h3>
        <ul data-attention>
          <.row
            :for={row <- part.rows}
            row={row}
            organisation={@organisation}
            now={@now}
            members={@members}
            user={@user}
          />
        </ul>
        <p>
          <span :if={part.total > length(part.rows)}>
            These are the first {length(part.rows)} of {part.total}.
          </span>
          <.link navigate={part_path(@organisation, part.part)}>
            {link_words(part.part)} <.icon name="chevron-right" />
          </.link>
        </p>
      </section>
    </section>
    """
  end

  defp summary(1), do: "1 thing needs attention now."
  defp summary(total), do: "#{total} things need attention now."

  defp title(part), do: @parts |> Keyword.fetch!(part) |> elem(0)
  defp link_words(part), do: @parts |> Keyword.fetch!(part) |> elem(1)

  defp part_path(organisation, :tasks), do: ~p"/o/#{organisation.short_name}/tasks"
  defp part_path(organisation, :inventory), do: ~p"/o/#{organisation.short_name}/inventory"
  defp part_path(organisation, :residents), do: ~p"/o/#{organisation.short_name}/residents"
  defp part_path(organisation, :housing), do: ~p"/o/#{organisation.short_name}/housing"
  defp part_path(organisation, :transfers), do: ~p"/o/#{organisation.short_name}/transfers"

  attr :row, :map, required: true
  attr :organisation, :map, required: true
  attr :now, :any, required: true
  attr :members, :list, required: true
  attr :user, :map, required: true

  # One thing that needs somebody. The kind of the row says which one.
  defp row(%{row: %{kind: :task}} = assigns) do
    ~H"""
    <li id={"attention-task-#{@row.record.id}"}>
      <.link navigate={~p"/o/#{@organisation.short_name}/tasks#task-#{@row.record.id}"}>
        {@row.record.title}
      </.link>
      <.state kind={TaskWords.phase_kind(@row.phase)}>{TaskWords.phase(@row.phase)}</.state>
      <small>{due(@row.record, @organisation, @now)}</small>
      <small :if={Tasks.subject_names(@row.record) != []}>
        For {TaskComponents.for_words(@row.record)}
      </small>
      <small>{TaskComponents.who(@row.record, @members, @user)}</small>
    </li>
    """
  end

  defp row(%{row: %{kind: :stock}} = assigns) do
    ~H"""
    <li id={"attention-stock-#{@row.record.id}"}>
      <.link navigate={~p"/o/#{@organisation.short_name}/inventory/#{@row.record.id}"}>
        {@row.record.name}
      </.link>
      <.state :for={{words, kind} <- Enum.map(@row.faults, &InventoryWords.fault/1)} kind={kind}>
        {words}
      </.state>
      <small>{InventoryWords.quantity(@row.stock.level, @row.record)} in stock</small>
    </li>
    """
  end

  defp row(%{row: %{kind: :late_back}} = assigns) do
    ~H"""
    <li id={"attention-late-back-#{@row.record.id}"}>
      <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{@row.record.id}"}>
        {resident_name(@row.record)}
      </.link>
      <.state kind="alert">Late back</.state>
      <small>Expected back on {ResidentWords.date(@row.absence.expected_back_on)}</small>
      <small>{@row.absence.reason}</small>
    </li>
    """
  end

  defp row(%{row: %{kind: :expected}} = assigns) do
    ~H"""
    <li id={"attention-expected-#{@row.record.id}"}>
      <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{@row.record.id}"}>
        {resident_name(@row.record)}
      </.link>
      <.state kind={ResidentWords.status_kind(:expected)}>
        {ResidentWords.status(:expected)}
      </.state>
      <small>No arrival is recorded</small>
    </li>
    """
  end

  defp row(%{row: %{kind: :over_capacity}} = assigns) do
    ~H"""
    <li id={"attention-over-capacity-#{@row.record.id}"}>
      <.link navigate={~p"/o/#{@organisation.short_name}/housing/#{@row.record.id}"}>
        {@row.record.name}
      </.link>
      <.state kind="alert">Over its capacity</.state>
      <small>{LocationComponents.occupancy(%{count: @row.count, location: @row.record})}</small>
    </li>
    """
  end

  defp row(%{row: %{kind: :transfer}} = assigns) do
    ~H"""
    <li id={"attention-transfer-#{@row.record.id}"}>
      <.link navigate={~p"/o/#{@organisation.short_name}/transfers#transfer-#{@row.record.id}"}>
        Transfer of {@row.record.resident_name || "a resident"}
      </.link>
      <.state kind={TransferWords.state(:sent) |> elem(1)}>
        {TransferWords.state(:sent) |> elem(0)}
      </.state>
      <small>From {other_name(@row.record, @organisation)}</small>
      <small>
        Sent on {ResidentWords.date(Accounts.local_date(@organisation, @row.record.sent_at))}
      </small>
    </li>
    """
  end

  defp row(%{row: %{kind: :partner_request}} = assigns) do
    ~H"""
    <li id={"attention-partner-request-#{@row.record.id}"}>
      <.link navigate={~p"/o/#{@organisation.short_name}/partners#partnership-#{@row.record.id}"}>
        {other_name(@row.record, @organisation)}
      </.link>
      <.state kind="info">Asks to be a partner</.state>
    </li>
    """
  end

  # When a task is due: the time for a task of today, and the day too for a
  # task of an earlier day.
  defp due(task, organisation, now) do
    today = Accounts.local_date(organisation, now)

    if Accounts.local_date(organisation, task.due_at) == today,
      do: "Today, #{TaskComponents.due(task, organisation, false)}",
      else: TaskComponents.due(task, organisation, true)
  end

  defp resident_name(resident), do: resident.name || "A resident with no name"

  defp other_name(record, organisation) do
    case Transfers.other(record, organisation) do
      %{name: name} when is_binary(name) -> name
      _unknown -> "a refuge that Rescord does not know"
    end
  end
end
