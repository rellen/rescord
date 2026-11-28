defmodule RescordWeb.ReportComponents do
  @moduledoc """
  The parts of a page that ask for a report (ADR 0076). Each is a plain link
  or a plain form with `GET` to `RescordWeb.ReportController`, so it works
  with no script, and the browser shows the PDF.
  """

  use RescordWeb, :html

  @doc """
  The documents of one resident, on its page: its record, with the part of
  the journal that the person chooses, and its cage card.
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
        <button type="submit">Make the record (PDF)</button>
      </form>
      <p>
        <a
          id="cage-card"
          href={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/card.pdf"}
        >
          Make the cage card (PDF)
        </a>
      </p>
    </section>
    """
  end

  @doc "A link to a report, for the actions of a header: `href` is a path of `RescordWeb.ReportController`."
  attr :href, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def report_link(assigns) do
    ~H"""
    <a id={@id} href={@href} data-variant="secondary">{render_slot(@inner_block)}</a>
    """
  end
end
