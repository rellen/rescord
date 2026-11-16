defmodule RescordWeb.HousingLive do
  @moduledoc """
  The housing of an organisation, at `/o/<short name>/housing`.

  The page draws the locations as a tree: each location is a card, and the
  locations inside it are smaller cards in that card. The same page serves
  each shape of housing, because an organisation defines its own kinds of
  location (ADR 0029).

  Each member reads the housing. An administrator adds a location here.
  """

  use RescordWeb, :live_view

  alias Rescord.{Lists, Locations}

  @impl true
  def mount(_params, _session, socket) do
    options = options(socket)
    {:ok, tree} = Locations.tree(options)
    {:ok, kinds} = Lists.offered_values(:location_kind, options)

    {:ok,
     assign(socket,
       page_title: "Housing",
       problems: [],
       tree: tree,
       kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}),
       places:
         for(
           {node, depth} <- Locations.flat(tree),
           do: {String.duplicate("– ", depth) <> node.location.name, node.location.id}
         ),
       can_add?: Locations.role_can?(socket.assigns.role, :location, :add),
       form:
         to_form(%{"name" => "", "kind_id" => "", "capacity" => "", "parent_id" => ""},
           as: :location
         )
     )}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  @impl true
  def handle_event("add", %{"location" => fields}, socket) when is_map(fields) do
    attributes = %{
      name: text(fields["name"]),
      kind_id: text(fields["kind_id"]),
      capacity: text(fields["capacity"]),
      parent_id: text(fields["parent_id"])
    }

    case Locations.add_location(attributes, options(socket)) do
      {:ok, _location} ->
        {:noreply,
         push_navigate(socket, to: ~p"/o/#{socket.assigns.organisation.short_name}/housing")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Rescord.Accounts.error_messages(error),
           form: to_form(fields, as: :location)
         )}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Housing
        <:subtitle>Where the residents of {@organisation.name} live</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p :if={@tree == []}>There is no location yet.</p>
      <.place :for={node <- @tree} node={node} organisation={@organisation} level={2} />

      <details :if={@can_add?}>
        <summary>New location</summary>
        <.form for={@form} id="location" phx-submit="add">
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
          <.input
            field={@form[:parent_id]}
            type="select"
            label="Inside"
            prompt="No other location"
            options={@places}
          />
          <footer><.button type="submit">Add the location</.button></footer>
        </.form>
      </details>
    </Layouts.app>
    """
  end

  attr :node, :map, required: true
  attr :organisation, :map, required: true
  attr :level, :integer, required: true, doc: "the level of the heading, from 2 to 6"

  @doc "One location as a card, with the locations inside it as cards in it."
  def place(assigns) do
    assigns = assign(assigns, free?: assigns.node.count == 0 and assigns.node.children == [])

    ~H"""
    <article data-place={if @free?, do: "free", else: "used"}>
      <header>
        <.dynamic_tag tag_name={"h#{min(@level, 6)}"}>
          <.link navigate={~p"/o/#{@organisation.short_name}/housing/#{@node.location.id}"}>{@node.location.name}</.link>
        </.dynamic_tag>
        <small>
          {if @node.location.kind, do: "#{@node.location.kind.label} · "}{occupancy(@node)}
        </small>
      </header>
      <.state :if={@node.over?} kind="alert">Over its capacity</.state>
      <ul :if={@node.residents != [] or @node.groups != []}>
        <li :for={placement <- @node.residents}>
          <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{placement.resident_id}"}>{placement.resident.name ||
            "No name yet"}</.link>
        </li>
        <li :for={{_placement, group, _members} <- @node.groups}>
          <.link navigate={~p"/o/#{@organisation.short_name}/groups/#{group.id}"}>{Rescord.Residents.group_name(
            group
          )}</.link>
          <span :if={Rescord.Residents.words(group)}>({Rescord.Residents.words(group)})</span>
        </li>
      </ul>
      <div :if={@node.children != []} data-places>
        <.place
          :for={child <- @node.children}
          node={child}
          organisation={@organisation}
          level={@level + 1}
        />
      </div>
    </article>
    """
  end

  @doc "The words for how full a location is: `2 of 2 residents`, `3 residents`, `Free`."
  def occupancy(%{count: 0}), do: "Free"

  def occupancy(%{count: count, location: %{capacity: capacity}}) when is_integer(capacity),
    do: "#{count} of #{capacity} residents"

  def occupancy(%{count: 1}), do: "1 resident"
  def occupancy(%{count: count}), do: "#{count} residents"
end
