defmodule RescordWeb.LiveChangesTest do
  @moduledoc """
  Holds how a page listens for changes (ADR 0096): it reads once for many
  changes, after a wait; it reads again for a change that comes later; it
  hears its own organisation and its own domains alone; and each other
  message still reaches the page.

  The page tests hold what a person sees (`RescordWeb.TaskPagesTest`,
  `RescordWeb.AttentionPagesTest`, `RescordWeb.TransferPagesTest`,
  `RescordWeb.ExpensePagesTest`). There the wait is 0. Here a small page
  counts its reads, and the changes are sent by hand, so the test needs no
  record.
  """

  use RescordWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Rescord.Accounts.Organisation
  alias Rescord.Changes
  alias Rescord.Changes.Change

  defmodule Page do
    @moduledoc false
    use Phoenix.LiveView

    def mount(_params, %{"organisation" => organisation, "wait" => wait}, socket) do
      {:ok,
       socket
       |> assign(organisation: organisation, reads: 0, others: 0)
       |> RescordWeb.LiveChanges.listen(
         [Rescord.Tasks, Rescord.Transfers],
         &update(&1, :reads, fn reads -> reads + 1 end),
         wait: wait
       )}
    end

    def handle_info(_message, socket), do: {:noreply, update(socket, :others, &(&1 + 1))}

    def render(assigns) do
      ~H"""
      <p id="counts">reads {@reads}, others {@others}</p>
      """
    end
  end

  # More than the wait of the page below, with room for a slow machine.
  @wait 60
  @after_wait 400

  defp organisation, do: %Organisation{id: Ecto.UUID.generate()}

  defp open(conn, organisation, wait) do
    {:ok, view, _html} =
      live_isolated(conn, Page, session: %{"organisation" => organisation, "wait" => wait})

    view
  end

  # Sends a change as the notifier does. A resource has one of the two
  # topics of its domain: here, the one of a resource in the schema.
  defp change(organisation, domain) do
    [topic | _shared] = Changes.topics(organisation, domain)

    Phoenix.PubSub.broadcast(Changes.pubsub(), topic, %Change{
      domain: domain,
      resource: nil,
      action: :update,
      type: :update,
      id: Ecto.UUID.generate()
    })
  end

  defp counts(view), do: view |> element("#counts") |> render()

  test "a page reads once for many changes, after the wait", %{conn: conn} do
    organisation = organisation()
    view = open(conn, organisation, @wait)

    for _ <- 1..5, do: change(organisation, Rescord.Tasks)
    assert counts(view) =~ "reads 0,"

    Process.sleep(@after_wait)
    assert counts(view) =~ "reads 1,"
  end

  test "a change after the read starts the next one", %{conn: conn} do
    organisation = organisation()
    view = open(conn, organisation, @wait)

    change(organisation, Rescord.Tasks)
    Process.sleep(@after_wait)
    assert counts(view) =~ "reads 1,"

    change(organisation, Rescord.Transfers)
    Process.sleep(@after_wait)
    assert counts(view) =~ "reads 2,"
  end

  test "with no wait, a page reads in the message of the change", %{conn: conn} do
    organisation = organisation()
    view = open(conn, organisation, 0)

    change(organisation, Rescord.Tasks)
    assert counts(view) =~ "reads 1,"
  end

  test "a page hears its organisation and its domains alone", %{conn: conn} do
    organisation = organisation()
    view = open(conn, organisation, 0)

    change(organisation(), Rescord.Tasks)
    change(organisation, Rescord.Inventory)
    assert counts(view) =~ "reads 0, others 0"
  end

  test "a change does not reach the page, and each other message does", %{conn: conn} do
    organisation = organisation()
    view = open(conn, organisation, 0)

    change(organisation, Rescord.Tasks)
    send(view.pid, :something_else)
    assert counts(view) =~ "reads 1, others 1"
  end
end
