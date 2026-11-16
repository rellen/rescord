defmodule RescordWeb.LocationLive do
  @moduledoc """
  One location, at `/o/<short name>/housing/<id>`.

  The page shows who lives in the location and which locations are inside
  it. A member puts a resident or a group there, at the time that the move
  happened when they give one, and ends a placement. An administrator
  changes the location, puts it inside another one, and closes it.

  A location that the person cannot read, and one that is not there, give
  the same answer: the housing page.
  """

  use RescordWeb, :live_view

  alias Rescord.{Lists, Locations, Residents}
  alias RescordWeb.HousingLive

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = options(socket)
    {:ok, tree} = Locations.tree(options)

    case is_binary(id) && Locations.find(tree, id) do
      %{} = node ->
        {:ok, residents} = Residents.residents([load: [:name]] ++ options)
        {:ok, groups} = Residents.groups_with_facts(options)
        {:ok, kinds} = Lists.offered_values(:location_kind, options)
        location = node.location
        inside = MapSet.new(Locations.flat([node]), fn {inner, _depth} -> inner.location.id end)

        {:ok,
         assign(socket,
           page_title: location.name,
           problems: [],
           node: node,
           residents: residents |> Enum.map(&{&1.name || "No name yet", &1.id}) |> Enum.sort(),
           groups: groups |> Enum.map(&{Residents.group_name(&1), &1.id}) |> Enum.sort(),
           kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}),
           # A location is not put inside itself, or inside a location in it.
           places:
             for(
               {other, depth} <- Locations.flat(tree),
               not MapSet.member?(inside, other.location.id),
               do: {String.duplicate("– ", depth) <> other.location.name, other.location.id}
             ),
           place_form:
             to_form(%{"resident_id" => "", "group_id" => "", "at" => ""}, as: :placement),
           move_form: to_form(%{"parent_id" => ""}, as: :move),
           form:
             to_form(
               %{
                 "name" => location.name,
                 "kind_id" => location.kind_id || "",
                 "capacity" => location.capacity || ""
               },
               as: :location
             )
         )}

      _no_location ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such location.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/housing")}
    end
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp path(socket) do
    ~p"/o/#{socket.assigns.organisation.short_name}/housing/#{socket.assigns.node.location.id}"
  end

  @impl true
  def handle_event("place", %{"placement" => fields}, socket) when is_map(fields) do
    subject =
      case {text(fields["resident_id"]), text(fields["group_id"])} do
        {nil, nil} -> {:error, "Choose a resident or a group"}
        {id, nil} -> {:ok, {:resident, id}}
        {nil, id} -> {:ok, {:group, id}}
        {_resident, _group} -> {:error, "Choose a resident or a group, and not both"}
      end

    with {:ok, subject} <- subject,
         {:ok, instant} <- Rescord.Accounts.instant(socket.assigns.organisation, fields["at"]) do
      options = if instant, do: [as_of: instant] ++ options(socket), else: options(socket)

      subject
      |> Locations.settle(socket.assigns.node.location.id, options)
      |> after_write(socket)
    else
      {:error, words} -> {:noreply, assign(socket, problems: [words])}
    end
  end

  def handle_event("finish", %{"id" => id}, socket) when is_binary(id) do
    node = socket.assigns.node
    placements = node.residents ++ Enum.map(node.groups, &elem(&1, 0))

    # Only a placement of this location: the page has them in hand.
    case Enum.find(placements, &(&1.id == id)) do
      nil -> {:noreply, socket}
      placement -> placement |> Locations.finish_placement(options(socket)) |> after_write(socket)
    end
  end

  def handle_event("revise", %{"location" => fields}, socket) when is_map(fields) do
    attributes = %{
      name: text(fields["name"]),
      kind_id: text(fields["kind_id"]),
      capacity: text(fields["capacity"])
    }

    socket.assigns.node.location
    |> Locations.revise_location(attributes, options(socket))
    |> after_write(socket)
  end

  def handle_event("move", %{"move" => %{"parent_id" => parent_id}}, socket) do
    socket.assigns.node.location
    |> Locations.move_location(text(parent_id), options(socket))
    |> after_write(socket)
  end

  def handle_event("close", _params, socket) do
    case Locations.close_location(socket.assigns.node.location, options(socket)) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "The location is closed.")
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/housing")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Opens the page again after a write, so that its forms are empty.
  defp after_write({:error, error}, socket),
    do: {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}

  defp after_write(_done, socket), do: {:noreply, push_navigate(socket, to: path(socket))}

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(value) when is_integer(value), do: value
  defp text(_other), do: nil

  defp can?(role, subject, action), do: Locations.role_can?(role, subject, action)

  defp resident_path(organisation, id), do: ~p"/o/#{organisation.short_name}/residents/#{id}"
  defp group_path(organisation, id), do: ~p"/o/#{organisation.short_name}/groups/#{id}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/housing"}>Housing</.link>
      </nav>

      <.header>
        {@node.location.name}
        <:subtitle>
          {if @node.location.kind, do: "#{@node.location.kind.label} · "}{HousingLive.occupancy(@node)}
          <.state :if={@node.over?} kind="alert">Over its capacity</.state>
        </:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section aria-labelledby="who-heading">
        <h2 id="who-heading">Who lives here</h2>
        <p :if={@node.residents == [] and @node.groups == []}>Nobody has a placement here.</p>
        <ul :if={@node.residents != [] or @node.groups != []}>
          <li :for={placement <- @node.residents}>
            <.link navigate={resident_path(@organisation, placement.resident_id)}>{placement.resident.name ||
              "No name yet"}</.link>
            <.button
              :if={can?(@role, :placement, :finish)}
              phx-click="finish"
              phx-value-id={placement.id}
              aria-label={"End the placement of #{placement.resident.name || "the resident with no name"}"}
            >
              End the placement
            </.button>
          </li>
          <li :for={{placement, group, members} <- @node.groups}>
            <.link navigate={group_path(@organisation, group.id)}>{Residents.group_name(group)}</.link>
            <span>
              ({length(members)} of {length(group.members)} members here)
            </span>
            <.button
              :if={can?(@role, :placement, :finish)}
              phx-click="finish"
              phx-value-id={placement.id}
              aria-label={"End the placement of #{Residents.group_name(group)}"}
            >
              End the placement
            </.button>
          </li>
        </ul>

        <details :if={can?(@role, :placement, :place)} id="put-here">
          <summary>Put a resident or a group here</summary>
          <.form for={@place_form} id="placement" phx-submit="place">
            <.input
              field={@place_form[:resident_id]}
              type="select"
              label="A resident"
              prompt="Choose"
              options={@residents}
            />
            <.input
              field={@place_form[:group_id]}
              type="select"
              label="Or a group"
              prompt="Choose"
              options={@groups}
            />
            <.input
              field={@place_form[:at]}
              type="datetime-local"
              label="When the move happened, if not now"
            />
            <footer><.button type="submit">Put here</.button></footer>
          </.form>
        </details>
      </section>

      <section :if={@node.children != []} aria-labelledby="inside-heading">
        <h2 id="inside-heading">Inside</h2>
        <div data-places>
          <HousingLive.place
            :for={child <- @node.children}
            node={child}
            organisation={@organisation}
            level={3}
          />
        </div>
      </section>

      <section :if={can?(@role, :location, :revise)} aria-labelledby="change-heading">
        <h2 id="change-heading">Change</h2>
        <details id="change-location">
          <summary>Change the location</summary>
          <.form for={@form} id="location" phx-submit="revise">
            <.input field={@form[:name]} type="text" label="Name" maxlength="80" required />
            <.input
              field={@form[:kind_id]}
              type="select"
              label="Kind"
              prompt="Not recorded"
              options={@kinds}
            />
            <.input
              field={@form[:capacity]}
              type="number"
              label="Capacity: the number of residents that it houses"
              min="1"
            />
            <footer><.button type="submit">Save the location</.button></footer>
          </.form>
        </details>
        <details id="move-location">
          <summary>Put this location inside another</summary>
          <.form for={@move_form} id="move" phx-submit="move">
            <.input
              field={@move_form[:parent_id]}
              type="select"
              label="Inside"
              prompt="No other location"
              options={@places}
            />
            <footer><.button type="submit">Move the location</.button></footer>
          </.form>
        </details>
        <details id="close-location">
          <summary>Close this location</summary>
          <p>Close a location that the organisation uses no more. Its history stays.</p>
          <.button phx-click="close">Close the location</.button>
        </details>
      </section>
    </Layouts.app>
    """
  end
end
