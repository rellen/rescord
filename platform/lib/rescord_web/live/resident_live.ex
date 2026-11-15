defmodule RescordWeb.ResidentLive do
  @moduledoc """
  One resident, at `/o/<short name>/residents/<id>`.

  The page shows each fact of the resident, and its stay: the arrival, an
  absence, and the departure. A member records each of those here, and adds
  or removes an identifier. The policy of each resource decides when the
  action runs.

  A resident that the person cannot read, and one that is not there, give
  the same answer: the list of the residents.
  """

  use RescordWeb, :live_view

  alias Rescord.{Lists, Residents}
  alias RescordWeb.ResidentWords

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load(socket, id) do
      {:ok, socket} ->
        {:ok, kinds} = Lists.values(:identifier_kind, options(socket))

        {:ok,
         socket
         |> assign(problems: [], today: Date.utc_today())
         |> assign(identifier_kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}))
         |> assign_forms()}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such resident.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}
    end
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp load(socket, id) do
    with true <- is_binary(id),
         {:ok, %{} = resident} <- Residents.resident_with_facts(id, options(socket)) do
      {:ok,
       assign(socket,
         resident: resident,
         page_title: resident.name || "A resident with no name",
         names: Residents.name_history(resident.id, options(socket)),
         desex_statuses: Residents.desex_history(resident.id, options(socket))
       )}
    else
      _no_resident -> :error
    end
  end

  defp assign_forms(socket) do
    today = Date.to_iso8601(socket.assigns.today)

    assign(socket,
      arrival_form: to_form(%{"kind" => "", "arrived_on" => today, "note" => ""}, as: :arrival),
      departure_form:
        to_form(%{"kind" => "", "departed_on" => today, "note" => ""}, as: :departure),
      absence_form: to_form(%{"reason" => "", "expected_back_on" => ""}, as: :absence),
      identifier_form: to_form(%{"kind_id" => "", "value" => ""}, as: :identifier)
    )
  end

  @impl true
  def handle_event("record_arrival", %{"arrival" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      kind: params["kind"],
      arrived_on: params["arrived_on"],
      note: blank_to_nil(params["note"])
    }
    |> Residents.record_arrival(options(socket))
    |> after_write(socket, "The arrival is recorded.")
  end

  def handle_event("record_departure", %{"departure" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      kind: params["kind"],
      departed_on: params["departed_on"],
      note: blank_to_nil(params["note"])
    }
    |> Residents.record_departure(options(socket))
    |> after_write(socket, "The departure is recorded.")
  end

  def handle_event("withdraw_departure", _params, socket) do
    case socket.assigns.resident.departure do
      nil ->
        {:noreply, socket}

      departure ->
        departure |> Residents.withdraw_departure(options(socket)) |> after_write(socket)
    end
  end

  def handle_event("start_absence", %{"absence" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      reason: params["reason"],
      expected_back_on: blank_to_nil(params["expected_back_on"])
    }
    |> Residents.start_absence(options(socket))
    |> after_write(socket)
  end

  def handle_event("finish_absence", _params, socket) do
    case socket.assigns.resident.absence do
      nil -> {:noreply, socket}
      absence -> absence |> Residents.finish_absence(options(socket)) |> after_write(socket)
    end
  end

  def handle_event("add_identifier", %{"identifier" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      kind_id: blank_to_nil(params["kind_id"]),
      value: params["value"]
    }
    |> Residents.add_identifier(options(socket))
    |> after_write(socket)
  end

  def handle_event("remove_identifier", %{"id" => id}, socket) when is_binary(id) do
    # Only an identifier of this resident: the page has them in hand.
    case Enum.find(socket.assigns.resident.identifiers, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      identifier ->
        identifier |> Residents.remove_identifier(options(socket)) |> after_write(socket)
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Opens the page again after a write, or shows what was wrong. A new page
  # reads the resident again, and its forms are empty: a form that stays on
  # the page keeps what the person typed.
  defp after_write(result, socket, words \\ nil) do
    case result do
      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}

      _done ->
        socket = if words, do: put_flash(socket, :info, words), else: socket

        {:noreply,
         push_navigate(socket,
           to:
             ~p"/o/#{socket.assigns.organisation.short_name}/residents/#{socket.assigns.resident.id}"
         )}
    end
  end

  defp blank_to_nil(text) when is_binary(text),
    do: if(String.trim(text) == "", do: nil, else: text)

  defp blank_to_nil(_other), do: nil

  defp can?(role, subject, action), do: Residents.role_can?(role, subject, action)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/residents"}>Residents</.link>
      </nav>

      <.header>
        {@resident.name || "A resident with no name"}
        <:subtitle>
          {@resident.species.label} · {ResidentWords.sex(@resident.sex)} ·
          <.state kind={ResidentWords.status_kind(@resident.status)}>
            {ResidentWords.status(@resident.status)}
          </.state>
        </:subtitle>
        <:actions>
          <.link
            :if={can?(@role, :resident, :revise)}
            navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/edit"}
            data-variant="secondary"
          >
            Change the facts
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section aria-labelledby="about-heading">
        <h2 id="about-heading">About</h2>
        <.list>
          <:item title="Species">{@resident.species.label}</:item>
          <:item title="Sex">{ResidentWords.sex(@resident.sex)}</:item>
          <:item title="Desex status">{ResidentWords.desex(@resident.desex_status)}</:item>
          <:item title="Born">{born(@resident, @today)}</:item>
          <:item title="Breed">{labels(@resident.resident_breeds, :breed)}</:item>
          <:item title="Colour">{labels(@resident.resident_colours, :colour)}</:item>
          <:item title="Size class">{label(@resident.size_class)}</:item>
          <:item title="Coat">{label(@resident.coat)}</:item>
          <:item title="Temperament">
            {labels(@resident.resident_temperaments, :temperament)}
          </:item>
        </.list>
      </section>

      <section aria-labelledby="stay-heading">
        <h2 id="stay-heading">Stay</h2>

        <.list :if={@resident.arrival}>
          <:item title="Arrival">
            {ResidentWords.arrival(@resident.arrival.kind)}, {ResidentWords.date(
              @resident.arrival.arrived_on
            )}
          </:item>
          <:item :if={@resident.arrival.note} title="Note about the arrival">
            {@resident.arrival.note}
          </:item>
        </.list>

        <details :if={is_nil(@resident.arrival) and can?(@role, :arrival, :record)} open>
          <summary>Record the arrival</summary>
          <.form for={@arrival_form} id="arrival" phx-submit="record_arrival">
            <.input
              field={@arrival_form[:kind]}
              type="select"
              label="How the resident came"
              prompt="Choose"
              options={ResidentWords.options(:arrival)}
              required
            />
            <.input field={@arrival_form[:arrived_on]} type="date" label="Date" required />
            <.input field={@arrival_form[:note]} type="text" label="Note" />
            <footer><.button type="submit">Record the arrival</.button></footer>
          </.form>
        </details>

        <div :if={@resident.absence}>
          <.list>
            <:item title="Away">{@resident.absence.reason}</:item>
            <:item :if={@resident.absence.expected_back_on} title="Expected back">
              {ResidentWords.date(@resident.absence.expected_back_on)}
            </:item>
          </.list>
          <.button :if={can?(@role, :absence, :finish)} phx-click="finish_absence">
            Mark as back
          </.button>
        </div>

        <details :if={@resident.status == :in_care and can?(@role, :absence, :start)}>
          <summary>Mark as away for a time</summary>
          <.form for={@absence_form} id="absence" phx-submit="start_absence">
            <.input field={@absence_form[:reason]} type="text" label="Where and why" required />
            <.input field={@absence_form[:expected_back_on]} type="date" label="Expected back" />
            <footer><.button type="submit">Mark as away</.button></footer>
          </.form>
        </details>

        <div :if={@resident.departure}>
          <.list>
            <:item title="Departure">
              {ResidentWords.departure(@resident.departure.kind)}, {ResidentWords.date(
                @resident.departure.departed_on
              )}
            </:item>
            <:item :if={@resident.departure.note} title="Note about the departure">
              {@resident.departure.note}
            </:item>
          </.list>
          <.button :if={can?(@role, :departure, :withdraw)} phx-click="withdraw_departure">
            Withdraw the departure
          </.button>
        </div>

        <details :if={
          @resident.arrival && is_nil(@resident.departure) && can?(@role, :departure, :record)
        }>
          <summary>Record the departure</summary>
          <.form for={@departure_form} id="departure" phx-submit="record_departure">
            <.input
              field={@departure_form[:kind]}
              type="select"
              label="How the resident left"
              prompt="Choose"
              options={ResidentWords.options(:departure)}
              required
            />
            <.input field={@departure_form[:departed_on]} type="date" label="Date" required />
            <.input field={@departure_form[:note]} type="text" label="How and why" />
            <footer><.button type="submit">Record the departure</.button></footer>
          </.form>
        </details>
      </section>

      <section aria-labelledby="identifiers-heading">
        <h2 id="identifiers-heading">Identifiers</h2>
        <p :if={@resident.identifiers == []}>No identifier is recorded.</p>
        <ul :if={@resident.identifiers != []}>
          <li :for={identifier <- @resident.identifiers}>
            {identifier.kind.label}: {identifier.value}
            <.button
              :if={can?(@role, :identifier, :remove)}
              phx-click="remove_identifier"
              phx-value-id={identifier.id}
              aria-label={"Remove the #{identifier.kind.label} #{identifier.value}"}
            >
              Remove
            </.button>
          </li>
        </ul>

        <details :if={can?(@role, :identifier, :add) and @identifier_kinds != []}>
          <summary>Add an identifier</summary>
          <.form for={@identifier_form} id="identifier" phx-submit="add_identifier">
            <.input
              field={@identifier_form[:kind_id]}
              type="select"
              label="Kind"
              prompt="Choose"
              options={@identifier_kinds}
              required
            />
            <.input field={@identifier_form[:value]} type="text" label="Number or mark" required />
            <footer><.button type="submit">Add the identifier</.button></footer>
          </.form>
        </details>
        <p :if={@identifier_kinds == []}>
          The list of identifier kinds is empty. An administrator adds a kind on <.link navigate={
            ~p"/o/#{@organisation.short_name}/lists"
          }>the lists page</.link>.
        </p>
      </section>

      <section
        :if={length(@names) > 1 or length(@desex_statuses) > 1}
        aria-labelledby="history-heading"
      >
        <h2 id="history-heading">History</h2>

        <div :if={length(@names) > 1}>
          <h3>Names</h3>
          <ol>
            <li :for={name <- @names}>
              {name.value}, from
              <time datetime={DateTime.to_iso8601(name.from)}>{ResidentWords.date(
                DateTime.to_date(name.from)
              )}</time>
            </li>
          </ol>
        </div>

        <div :if={length(@desex_statuses) > 1}>
          <h3>Desex status</h3>
          <ol>
            <li :for={status <- @desex_statuses}>
              {ResidentWords.desex(status.value)}, from
              <time datetime={DateTime.to_iso8601(status.from)}>{ResidentWords.date(
                DateTime.to_date(status.from)
              )}</time>
            </li>
          </ol>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp label(nil), do: "Not recorded"
  defp label(value), do: value.label

  defp labels([], _value), do: "Not recorded"

  defp labels(ties, value) do
    ties |> Enum.map(&to_string(Map.fetch!(&1, value).label)) |> Enum.sort() |> Enum.join(", ")
  end

  defp born(%{born_on: nil}, _today), do: "Not recorded"

  defp born(resident, today) do
    date = ResidentWords.date(resident.born_on)
    date = if resident.born_on_estimated?, do: "About #{date}", else: date

    case ResidentWords.age(resident.born_on, today) do
      nil -> date
      age -> "#{date} (#{age} old)"
    end
  end
end
