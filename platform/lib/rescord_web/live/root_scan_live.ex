defmodule RescordWeb.RootScanLive do
  @moduledoc """
  The virus scan of the PDFs, for a root user, at `/root/scan` (issue 37,
  ADR 0113): on or off, and the address of clamd. "Test" sends `PING` to
  the address in the form, saved or not, so a root user sees that clamd
  answers before the scan refuses each PDF that it cannot scan. The live
  session lets only a root user in, and the policy of
  `Rescord.Storage.Scan.Settings` refuses each other person.

  No setting of the scan is in the environment (ADR 0068): this page is
  where it is set.
  """

  use RescordWeb, :live_view

  alias Rescord.Accounts
  alias Rescord.Storage.Scan

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Virus scan", problems: [], test: nil)
     |> load()}
  end

  defp options(socket), do: [actor: socket.assigns.current_user]

  defp load(socket) do
    settings = Scan.settings()

    fields = %{
      "scan_on" => to_string(settings.scan_on || false),
      "address" => settings.address || ""
    }

    assign(socket, settings: settings, fields: fields, form: to_form(fields, as: :scan))
  end

  @impl true
  def handle_event("change", %{"scan" => %{} = fields}, socket) do
    fields = Shoddy.Maps.text_fields(fields)
    {:noreply, assign(socket, fields: fields, form: to_form(fields, as: :scan))}
  end

  def handle_event("save", %{"scan" => %{} = fields}, socket) do
    attributes = %{scan_on: fields["scan_on"] == "true", address: address(fields["address"])}

    case Scan.save_settings(attributes, options(socket)) do
      {:ok, _settings} ->
        {:noreply,
         socket |> assign(problems: [], test: nil) |> put_flash(:info, "Saved.") |> load()}

      {:error, error} ->
        fields = Shoddy.Maps.text_fields(fields)

        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           fields: fields,
           form: to_form(fields, as: :scan)
         )}
    end
  end

  def handle_event("test", _params, socket) do
    address = address(socket.assigns.fields["address"])

    test =
      case Scan.ping(address) do
        :ok -> {:ok, "clamd at #{address} answers."}
        {:fault, words} -> {:fault, "clamd at #{address || "no address"} #{words}."}
      end

    {:noreply, assign(socket, test: test)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp address(nil), do: nil

  defp address(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/root"}>Root</.link>
      </nav>

      <.header>
        Virus scan
        <:subtitle>
          <.state :if={@settings.scan_on} kind="ok">On</.state>
          <.state :if={!@settings.scan_on} kind="none">Off</.state>
        </:subtitle>
      </.header>

      <section aria-labelledby="about-heading">
        <h2 id="about-heading">What the scan does</h2>
        <p>
          With the scan on, each PDF of a journal entry or of an expense goes to clamd, the daemon of ClamAV, before Rescord keeps it. A file that clamd finds harmful is refused. While clamd does not answer, each PDF is refused too, so that no PDF gets in without a scan.
        </p>
        <p>
          A photo is not scanned: Rescord writes each photo again from its pixels, with nothing else in it. The PDFs that Rescord has already are not scanned. clamd runs apart from Rescord, and its signatures take a few GB of memory. Its
          <code>StreamMaxLength</code>
          must be at least 20M, the largest file of Rescord.
        </p>
      </section>

      <.problems list={@problems} />

      <.form for={@form} id="scan-settings" phx-change="change" phx-submit="save">
        <h2>The settings</h2>
        <.input
          field={@form[:address]}
          type="text"
          label="Address of clamd"
          placeholder="clamd:3310"
          hint="host:port for TCP, such as clamd:3310, or the path of its Unix socket, such as /run/clamav/clamd.ctl."
        />
        <.input
          field={@form[:scan_on]}
          type="checkbox"
          label="Scan each PDF"
          hint="Test the address first: with the scan on and no answer of clamd, each PDF is refused."
        />
        <footer>
          <button type="submit">Save</button>
          <button type="button" data-variant="secondary" phx-click="test">Test</button>
        </footer>
      </.form>

      <%!-- Always there, so that a screen reader reads the result when it comes. --%>
      <p id="scan-test" role="status">
        <%= case @test do %>
          <% {:ok, words} -> %>
            <.state kind="ok">Answers</.state>
            {words}
          <% {:fault, words} -> %>
            <.state kind="alert">No answer</.state>
            {words}
          <% nil -> %>
        <% end %>
      </p>
    </Layouts.app>
    """
  end
end
