defmodule RescordWeb.RootHealthLive do
  @moduledoc """
  The sanity checks of the server, for a root user, at `/root/health`
  (ADR 0114, issue 38): what each check found at its last run, for the
  server and for each organisation, since when, and what a fault means.
  "Run each check now" runs them all in a task of the page.

  A result holds a count and ids, never a value of a row. The ids are
  there for a root user to find the rows, not links into an organisation.
  """

  use RescordWeb, :live_view

  import RescordWeb.HealthComponents

  alias Rescord.Health

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Sanity checks", running?: false) |> load()}
  end

  defp load(socket) do
    actor = socket.assigns.current_user
    results = Health.results(actor: actor)

    groups =
      results
      |> Enum.chunk_by(& &1.organisation_id)
      |> Enum.map(fn [first | _rest] = rows -> {first.organisation, rows} end)

    assign(socket,
      groups: groups,
      summary: Health.summary(actor: actor),
      checks: Health.checks()
    )
  end

  @impl true
  def handle_event("run", _params, socket) do
    if socket.assigns.running? do
      {:noreply, socket}
    else
      actor = socket.assigns.current_user

      {:noreply,
       socket
       |> assign(running?: true)
       |> start_async(:run, fn -> Health.run_now(actor: actor) end)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:run, {:ok, :ok}, socket) do
    {:noreply, socket |> assign(running?: false) |> put_flash(:info, "Each check ran.") |> load()}
  end

  def handle_async(:run, _other, socket) do
    {:noreply,
     socket
     |> assign(running?: false)
     |> put_flash(:error, "The checks did not finish. The log says why.")
     |> load()}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <.header icon={Icons.section(:health)}>
        <:crumb navigate={~p"/root"}>Root</:crumb>
        Sanity checks
        <:subtitle>
          What the checks of the data and of the server found. They run on their own, and change nothing.
        </:subtitle>
      </.header>

      <.overview summary={@summary} running?={@running?} />
      <.results :for={{organisation, rows} <- @groups} organisation={organisation} rows={rows} />
      <.checks checks={@checks} />
    </Layouts.app>
    """
  end
end
