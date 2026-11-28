defmodule RescordWeb.ExportLive do
  @moduledoc """
  The export of the data of an organisation, at `/o/<short name>/export`
  (ADR 0054). A person whose role has the power `export` chooses a date,
  today at first, and downloads one ZIP with a CSV file for each table, as
  the data stood at the end of that day.

  The form posts to `RescordWeb.ExportController`, because a page of
  LiveView cannot send a file. A person without the power reads why there is
  no form.
  """

  use RescordWeb, :live_view

  alias Rescord.Accounts

  @impl true
  def mount(_params, _session, socket) do
    today = Accounts.today(socket.assigns.organisation)

    {:ok,
     assign(socket,
       page_title: "Export",
       can_export?: Accounts.role_can_export?(socket.assigns.role),
       today: Date.to_iso8601(today)
     )}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:settings}
    >
      <.header icon={Icons.section(:export)}>
        Export the data
        <:subtitle>A copy of the data of {@organisation.name}, as files of CSV.</:subtitle>
      </.header>

      <section aria-labelledby="export-heading">
        <h2 id="export-heading">What the export holds</h2>
        <p>
          One ZIP file, with a CSV file for each table: the residents and their facts, the
          families and the groups, the housing and the placements, the journal with its
          medical details, the tasks and the routines, the inventory, the lists of values,
          the roles and the members. A file <code>README.txt</code>
          says what each file and column holds, and how the files name each other.
        </p>
        <p>
          The data is as it stood at the end of the day that you choose, in the time zone of
          the organisation. The tasks, the routines and the members keep no history, so they
          are as they are now. The photos and the PDFs of the journal are not in the export.
        </p>
      </section>

      <section :if={@can_export?} aria-labelledby="download-heading">
        <h2 id="download-heading">Download</h2>
        <.form
          for={%{}}
          as={:export}
          id="export"
          action={~p"/o/#{@organisation.short_name}/export"}
          method="post"
        >
          <.input
            id="export-on"
            name="export[on]"
            type="date"
            label="As of the end of"
            value={@today}
            max={@today}
            required
          />
          <button type="submit"><.icon name="arrow-down-tray" /> Download the export</button>
        </.form>
      </section>

      <p :if={!@can_export?} id="no-export">
        Your role cannot export the data. An administrator can give a role the power to export.
      </p>
    </Layouts.app>
    """
  end
end
