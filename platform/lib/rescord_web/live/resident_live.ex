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
        {:ok, kinds} = Lists.offered_values(:identifier_kind, options(socket))

        {:ok,
         socket
         |> assign(problems: [], today: Rescord.Accounts.today(socket.assigns.organisation))
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
         desex_statuses: Residents.desex_history(resident.id, options(socket)),
         relations: Residents.relations(resident.id, options(socket))
       )
       |> assign_choices()}
    else
      _no_resident -> :error
    end
  end

  # The residents and the families that a form of the relations offers.
  defp assign_choices(socket) do
    {:ok, residents} = Residents.residents([load: [:name]] ++ options(socket))
    {:ok, families} = Residents.families(options(socket))
    relations = socket.assigns.relations
    in_family = MapSet.new(relations.families, & &1.family_id)

    assign(socket,
      other_residents:
        residents
        |> Enum.reject(&(&1.id == socket.assigns.resident.id))
        |> Enum.map(&{&1.name || "No name yet", &1.id})
        |> Enum.sort(),
      other_families:
        families
        |> Enum.reject(&MapSet.member?(in_family, &1.id))
        |> Enum.map(&{&1.name, &1.id})
        |> Enum.sort(),
      parent_form: to_form(%{"parent_id" => "", "role" => "mother"}, as: :parent),
      family_form: to_form(%{"family_id" => "", "name" => ""}, as: :family)
    )
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

  def handle_event("record_parent", %{"parent" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      parent_id: blank_to_nil(params["parent_id"]),
      role: params["role"]
    }
    |> Residents.record_parent(options(socket))
    |> after_write(socket)
  end

  def handle_event("remove_parent", %{"id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.relations.parents, &(&1.id == id)) do
      nil -> {:noreply, socket}
      link -> link |> Residents.remove_parent(options(socket)) |> after_write(socket)
    end
  end

  # A family that is there, or a new one with the name that the person gave.
  def handle_event("add_to_family", %{"family" => params}, socket) when is_map(params) do
    family =
      case {blank_to_nil(params["family_id"]), blank_to_nil(params["name"])} do
        {nil, nil} -> {:error, :nothing}
        {nil, name} -> Residents.name_family(name, options(socket))
        {id, _name} -> {:ok, %{id: id}}
      end

    case family do
      {:ok, %{id: family_id}} ->
        %{resident_id: socket.assigns.resident.id, family_id: family_id}
        |> Residents.add_to_family(options(socket))
        |> after_write(socket)

      {:error, :nothing} ->
        {:noreply, assign(socket, problems: ["Choose a family, or give a new one a name"])}

      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}
    end
  end

  def handle_event("remove_from_family", %{"id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.relations.families, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      membership ->
        membership |> Residents.remove_from_family(options(socket)) |> after_write(socket)
    end
  end

  def handle_event("remove_resident", _params, socket) do
    case Residents.remove_resident(socket.assigns.resident, options(socket)) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "The resident is removed.")
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}
    end
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

  # Short names for the paths, so that a link and its text are on one line:
  # a line break inside a link is a space that the browser underlines.
  defp resident_path(organisation, id), do: ~p"/o/#{organisation.short_name}/residents/#{id}"
  defp group_path(organisation, id), do: ~p"/o/#{organisation.short_name}/groups/#{id}"

  defp name(resident), do: resident.name || "No name yet"

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
          <p :if={can?(@role, :absence, :finish)}>
            <.button phx-click="finish_absence">Mark as back</.button>
          </p>
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
          <p :if={can?(@role, :departure, :withdraw)}>
            <.button phx-click="withdraw_departure">Withdraw the departure</.button>
          </p>
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

      <section aria-labelledby="relations-heading">
        <h2 id="relations-heading">Family and groups</h2>

        <h3>Parents</h3>
        <p :if={@relations.parents == []}>No parent is recorded.</p>
        <ul :if={@relations.parents != []}>
          <li :for={link <- @relations.parents}>
            {ResidentWords.kin(link.role)}:
            <.link navigate={resident_path(@organisation, link.parent_id)}>{name(link.parent)}</.link>
            <.button
              :if={can?(@role, :parent, :remove)}
              phx-click="remove_parent"
              phx-value-id={link.id}
              aria-label={"Remove the #{String.downcase(ResidentWords.kin(link.role))} #{link.parent.name}"}
            >
              Remove
            </.button>
          </li>
        </ul>

        <details :if={can?(@role, :parent, :record) and @other_residents != []}>
          <summary>Add a parent</summary>
          <.form for={@parent_form} id="parent" phx-submit="record_parent">
            <.input
              field={@parent_form[:parent_id]}
              type="select"
              label="Parent"
              prompt="Choose"
              options={@other_residents}
              required
            />
            <.input
              field={@parent_form[:role]}
              type="select"
              label="Mother or father"
              options={ResidentWords.options(:kin)}
            />
            <footer><.button type="submit">Add the parent</.button></footer>
          </.form>
        </details>

        <div :if={@relations.young != []}>
          <h3>Young</h3>
          <ul>
            <li :for={link <- @relations.young}>
              <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{link.resident_id}"}>
                {link.resident.name || "No name yet"}
              </.link>
            </li>
          </ul>
        </div>

        <h3>Families</h3>
        <p :if={@relations.families == []}>The resident is in no family.</p>
        <ul :if={@relations.families != []}>
          <li :for={membership <- @relations.families}>
            {membership.family.name}
            <.button
              :if={can?(@role, :family_member, :remove)}
              phx-click="remove_from_family"
              phx-value-id={membership.id}
              aria-label={"Take the resident out of #{membership.family.name}"}
            >
              Take out
            </.button>
          </li>
        </ul>

        <details :if={can?(@role, :family_member, :add)}>
          <summary>Add to a family</summary>
          <.form for={@family_form} id="family" phx-submit="add_to_family">
            <.input
              :if={@other_families != []}
              field={@family_form[:family_id]}
              type="select"
              label="A family that is there"
              prompt="Choose"
              options={@other_families}
            />
            <.input
              field={@family_form[:name]}
              type="text"
              label="Or the name of a new family"
              maxlength="80"
            />
            <footer><.button type="submit">Add to the family</.button></footer>
          </.form>
        </details>

        <h3>Groups</h3>
        <p :if={@relations.groups == []}>
          The resident is in no group. A member adds it on <.link navigate={
            ~p"/o/#{@organisation.short_name}/groups"
          }>the groups page</.link>.
        </p>
        <ul :if={@relations.groups != []}>
          <li :for={{_membership, group} <- @relations.groups}>
            <.link navigate={group_path(@organisation, group.id)}>{Residents.group_name(group)}</.link>
            <span :if={Residents.words(group)}>({Residents.words(group)})</span>
          </li>
        </ul>
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
                Rescord.Accounts.local_date(@organisation, name.from)
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
                Rescord.Accounts.local_date(@organisation, status.from)
              )}</time>
            </li>
          </ol>
        </div>
      </section>
      <section :if={can?(@role, :resident, :remove)} aria-labelledby="remove-heading">
        <h2 id="remove-heading">Remove</h2>
        <details>
          <summary>Remove this resident</summary>
          <p>
            Remove a resident only when somebody recorded it by mistake. For a resident that left,
            record the departure.
          </p>
          <.button phx-click="remove_resident">Remove the resident</.button>
        </details>
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
    date = if resident.born_on_estimated, do: "About #{date}", else: date

    case ResidentWords.age(resident.born_on, today) do
      nil -> date
      age -> "#{date} (#{age} old)"
    end
  end
end
