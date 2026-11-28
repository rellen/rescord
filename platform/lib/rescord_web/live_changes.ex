defmodule RescordWeb.LiveChanges do
  @moduledoc """
  A page that shows what another person changed, without a reload
  (ADR 0096).

  A page calls `listen/3` in `mount/3`, with the domains that it shows and
  with the function that reads them again:

      def mount(_params, _session, socket) do
        {:ok,
         socket
         |> assign(page_title: "Tasks")
         |> LiveChanges.listen([Tasks], &assign_tasks/1)}
      end

  When a record of one of those domains changes in the organisation of the
  page, the page waits a moment and then calls the function once. The
  function reads as the person of the page, through the code interface of
  the domain, as `mount/3` does. A change carries no record
  (`Rescord.Changes`), so there is nothing here to keep from a person: the
  policies answer the read.

  ## What the function must do, and must not do

    * Read again what the page shows of those domains, and assign it.
    * Leave the forms alone. A person who is typing keeps what they typed
      when the form is not assigned again.
    * For a `Cinder.collection`, call
      `Cinder.refresh_table(socket, "<id>", silent: true)`, which keeps the
      rows on the page while it reads.

  ## One read for many changes

  One action can write several records, and a job can write many. The
  first change starts a wait of 250 milliseconds, and the changes that
  come in that time start nothing more. A change that comes after the read
  has begun starts the next wait, so the page never misses the last one.

  ## The page that wrote

  A page does not hear its own writes (`Rescord.Changes`). It reads again in
  its own event, as it did before.

  ## In a test

  The wait is 0 in the tests (`config/test.exs`): the page reads again at
  once, in the message of the change. So a test writes, and then renders
  the view. `RescordWeb.LiveChangesTest` holds the wait itself. For a page
  with a collection of Cinder, render with `render_changes/1` of
  `RescordWeb.ConnCase`, which waits for the read of Cinder.

  A test of a page that has not read yet, such as a press on a button a
  moment after another person pressed it, opens the page inside
  `RescordWeb.ConnCase.with_slow_changes/1`, where the wait is a minute.
  """

  alias Phoenix.LiveView.Socket
  alias Rescord.Changes
  alias Rescord.Changes.Change
  alias ShoddyPhoenix.LiveView
  alias ShoddyPhoenix.LiveView.Subscriptions

  # The time that a page waits after the first change, in milliseconds.
  @wait 250

  # The message that ends the wait.
  @read_again {__MODULE__, :read_again}

  # Whether the page waits now, in the private data of the socket.
  @waiting :rescord_live_changes_waiting

  @doc """
  Makes the page read again, with `reload`, after a change of one of
  `domains` in its organisation.

  It does nothing for a socket that is not connected: the first render is a
  plain HTTP response, and its process must not subscribe. Options:

    * `:wait` - the time to wait after the first change, in milliseconds.
      0 reads again at once.
  """
  @spec listen(Socket.t(), [module()], (Socket.t() -> Socket.t()), keyword()) :: Socket.t()
  def listen(%Socket{} = socket, domains, reload, opts \\ [])
      when is_list(domains) and is_function(reload, 1) do
    wait = Keyword.get_lazy(opts, :wait, &wait/0)

    LiveView.when_connected(socket, fn socket ->
      organisation = socket.assigns.organisation

      socket =
        for domain <- domains, topic <- Changes.topics(organisation, domain), reduce: socket do
          socket -> Subscriptions.subscribe(socket, Changes.pubsub(), topic, __MODULE__)
        end

      LiveView.put_hook(
        socket,
        __MODULE__,
        :handle_info,
        &handle_info(&1, &2, domains, reload, wait)
      )
    end)
  end

  # The tests set the wait, and nothing else does: it is not a setting of an
  # instance.
  defp wait, do: Keyword.get(Application.get_env(:rescord, __MODULE__, []), :wait, @wait)

  # A change of a domain that the page does not listen to is for another
  # part of the page, such as the count of the notifications or a widget.
  defp handle_info(%Change{domain: domain} = change, socket, domains, reload, wait) do
    if domain in domains, do: heard(change, socket, reload, wait), else: {:cont, socket}
  end

  defp handle_info(@read_again, socket, _domains, reload, _wait) do
    {:halt, socket |> Phoenix.LiveView.put_private(@waiting, false) |> reload.()}
  end

  defp handle_info(_message, socket, _domains, _reload, _wait), do: {:cont, socket}

  defp heard(%Change{}, socket, reload, 0), do: {:halt, reload.(socket)}

  defp heard(%Change{}, socket, _reload, wait) do
    if socket.private[@waiting] do
      {:halt, socket}
    else
      Process.send_after(self(), @read_again, wait)
      {:halt, Phoenix.LiveView.put_private(socket, @waiting, true)}
    end
  end
end
