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
    </ul>
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
