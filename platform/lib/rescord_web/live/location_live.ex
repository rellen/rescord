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

  import RescordWeb.LocationComponents

  alias Rescord.{Lists, Locations, Residents}

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
      case {non_blank(fields["resident_id"]), non_blank(fields["group_id"])} do
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
      name: non_blank(fields["name"]),
      kind_id: non_blank(fields["kind_id"]),
      capacity: non_blank(fields["capacity"])
    }

    socket.assigns.node.location
    |> Locations.revise_location(attributes, options(socket))
    |> after_write(socket)
  end

  def handle_event("move", %{"move" => %{"parent_id" => parent_id}}, socket) do
    socket.assigns.node.location
    |> Locations.move_location(non_blank(parent_id), options(socket))
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
          {if @node.location.kind, do: "#{@node.location.kind.label} · "}{occupancy(@node)}
          <.state :if={@node.over?} kind="alert">Over its capacity</.state>
        </:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <.who_lives_here
        node={@node}
        organisation={@organisation}
        role={@role}
        place_form={@place_form}
        residents={@residents}
        groups={@groups}
      />

      <.inside :if={@node.children != []} node={@node} organisation={@organisation} />

      <.change_location
        :if={can?(@role, :location, :revise)}
        form={@form}
        kinds={@kinds}
        move_form={@move_form}
        places={@places}
      />
    </Layouts.app>
    """
  end
end
