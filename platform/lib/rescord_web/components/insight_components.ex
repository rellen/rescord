defmodule RescordWeb.InsightComponents do
  @moduledoc """
  The parts of the pages of insights (ADR 0116): the list of those pages,
  which the page of the reports shows, and the key of a heat map.
  `RescordWeb.ChartComponents` draws the charts.
  """

  use RescordWeb, :html

  @doc """
  The pages of insights of an organisation: a card for each, with its
  name, which is the link, and the question that it answers.
  """
  attr :organisation, :map, required: true

  def insights(assigns) do
    ~H"""
    <ul data-insights>
      <li>
        <.link navigate={~p"/o/#{@organisation.short_name}/insights/care"}>
          Care, day by day
        </.link>
        <small>
          Are the routines kept? The tasks done on time on each day of the last six months,
          and the tasks of the next two weeks.
        </small>
      </li>
      <li>
        <.link navigate={~p"/o/#{@organisation.short_name}/insights/residents"}>
          Residents in care
        </.link>
        <small>
          How full is the refuge, against its room? The residents in care each day of the last
          year, and the arrivals and departures of each week.
        </small>
      </li>
      <li>
        <.link navigate={~p"/o/#{@organisation.short_name}/insights/conditions"}>
          Conditions by week
        </.link>
        <small>
          Is something spreading? The new cases of each condition in each of the last 12 weeks,
          and the cases that go on now.
        </small>
      </li>
      <li>
        <.link navigate={~p"/o/#{@organisation.short_name}/insights/hours"}>
          When the care is done
        </.link>
        <small>
          Which hours are busy, and which hours slip? The tasks done in each hour of the week over
          the last 12 weeks, and the share done late for each hour.
        </small>
      </li>
    </ul>
    """
  end

  @doc """
  The key of a chart: a swatch of each mark with its words. A swatch is
  `"line"`, `"rule"`, `"up"`, `"down"` or a step of the ramp, `1` to `4`.
  The swatches are decoration: the words say what each mark is.

  ## Examples

      <.key items={[{"line", "In care"}, {"rule", "Room"}]} />
  """
  attr :items, :list, required: true, doc: "a `{swatch, words}` for each mark"
  attr :rest, :global

  def key(assigns) do
    ~H"""
    <p data-key {@rest}>
      <span :for={{swatch, words} <- @items}>
        <span data-swatch={swatch} aria-hidden="true"></span> {words}
      </span>
    </p>
    """
  end

  @doc """
  The key of a heat map: a swatch of each step of the ramp with its words,
  and the dot of a cell that needs a look when `mark` has words. The
  swatches are decoration: the words say what each step is.

  ## Examples

      <.heat_key steps={["Under 80%", "80%", "90%", "97% or more"]} mark="Skipped or overdue" />
  """
  attr :steps, :list, required: true, doc: "the words of steps 1 to 4"
  attr :mark, :string, default: nil, doc: "the words of the dot"
  attr :rest, :global

  def heat_key(assigns) do
    assigns = assign(assigns, :numbered, Enum.with_index(assigns.steps, 1))

    ~H"""
    <p data-key {@rest}>
      <span :for={{words, step} <- @numbered}>
        <span data-swatch={step} aria-hidden="true"></span> {words}
      </span>
      <span :if={@mark}><span data-swatch="mark" aria-hidden="true"></span> {@mark}</span>
    </p>
    """
  end
end
