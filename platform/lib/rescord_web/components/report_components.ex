defmodule RescordWeb.ReportComponents do
  @moduledoc """
  The parts of a page that ask for a report (ADR 0076). Each is a plain link
  or a plain form with `GET` to `RescordWeb.ReportController`, so it works
  with no script, and the browser shows the PDF.
  """

  use RescordWeb, :html

  alias RescordWeb.ReportWords

  @doc """
  The control that chooses the paper of a report (ADR 0093), for a form
  that asks for one: a select with the name `paper`. `value` is the paper
  that is chosen at first, which is the one of the organisation.
  """
  attr :id, :string, required: true
  attr :value, :atom, required: true

  def paper_control(assigns) do
    ~H"""
    <.input
      id={@id}
      name="paper"
      type="select"
      label="Paper"
      options={ReportWords.paper_options()}
      value={Atom.to_string(@value)}
    />
    """
  end

  @doc """
  The paper of the reports of an organisation (ADR 0093), and the form that
  changes it.
  """
  attr :organisation, :any, required: true
  attr :can_change?, :any, required: true
  attr :problems, :list, default: []
  attr :problems_at, :any, default: nil

  def paper_setting(assigns) do
    ~H"""
    <section aria-labelledby="paper-heading">
      <h2 id="paper-heading">Paper of the reports</h2>
      <.problems list={@problems} at={@problems_at} here={:paper} />
      <p>
        A report of {@organisation.name} is a PDF on
        <strong>{ReportWords.paper_name(@organisation.paper_size)}</strong>
        paper. A person who makes a report can choose the other paper for that one document.
      </p>
      <form :if={@can_change?} id="paper" phx-submit="save_paper">
        <.input
          id="paper-size"
          name="paper[size]"
          type="select"
          label="Paper of a report"
          value={Atom.to_string(@organisation.paper_size)}
          options={ReportWords.paper_options()}
        />
        <footer><.button type="submit">Save the paper</.button></footer>
      </form>
    </section>
    """
  end

  @doc """
  The documents of one resident, on its page: its record, with the part of
  the journal that the person chooses, and its cage card. The two share the
  control of the paper, so the cage card is a second button of the form,
  which sends it to the address of the card.
  """
  attr :organisation, :map, required: true
  attr :resident, :map, required: true

  def resident_documents(assigns) do
    ~H"""
    <section id="documents" aria-labelledby="documents-heading">
      <h2 id="documents-heading">On paper</h2>
      <form
        id="record"
        action={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/record.pdf"}
      >
        <.input
          id="record-journal"
          name="journal"
          type="select"
          label="The record holds"
          options={[
            {"Its medical history", "medical"},
            {"Its whole journal", "all"},
            {"No journal", "none"}
          ]}
          value="medical"
        />
        <.input id="record-photos" name="photos" type="checkbox" label="With its photos" />
        <.paper_control id="record-paper" value={@organisation.paper_size} />
        <footer>
          <button type="submit"><.icon name="document-text" /> Make the record (PDF)</button>
          <button
            id="cage-card"
            type="submit"
            formaction={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/card.pdf"}
          >
            <.icon name="printer" /> Make the cage card (PDF)
          </button>
        </footer>
      </form>
    </section>
    """
  end

  @doc "A link to a report, for the actions of a header: `href` is a path of `RescordWeb.ReportController`."
  attr :href, :string, required: true
  attr :id, :string, default: nil
  attr :icon, :string, default: "document-chart", doc: "the shape before the words"
  slot :inner_block, required: true

  def report_link(assigns) do
    ~H"""
    <a id={@id} href={@href} data-variant="secondary">
      <.icon name={@icon} /> {render_slot(@inner_block)}
    </a>
    """
  end
end
