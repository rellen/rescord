defmodule RescordWeb.LocationComponents do
  @moduledoc """
  The parts of the pages of the housing (ADR 0029 and ADR 0037): a location
  as a card with the locations inside it, the residents and the groups of a
  location, and the forms that shape the housing.
  """

  use RescordWeb, :html

  alias Rescord.{Locations, Residents}

  @doc "The form of a new location, in a part of the page that is closed at first."
  attr :form, :any, required: true
  attr :kinds, :any, required: true
  attr :places, :any, required: true

  def new_location(assigns) do
    ~H"""
    <details id="new-location">
      <summary><.icon name="plus" /> New location</summary>
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
    """
  end

  attr :node, :map, required: true
  attr :organisation, :map, required: true
  attr :level, :integer, required: true, doc: "the level of the heading, from 2 to 6"

  @doc "One location as a card named by its heading, with the locations inside it as cards in it."
  def place(assigns) do
    assigns = assign(assigns, free?: assigns.node.count == 0 and assigns.node.children == [])

    ~H"""
    <article
      data-place={if @free?, do: "free", else: "used"}
      aria-labelledby={"place-#{@node.location.id}"}
    >
      <header>
        <.dynamic_tag tag_name={"h#{min(@level, 6)}"} id={"place-#{@node.location.id}"}>
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

  @doc "The words for how full a location is: `2 residents, room for 2`, `3 residents`, `Free`."
  def occupancy(%{count: 0}), do: "Free"

  def occupancy(%{count: count, location: %{capacity: capacity}}) when is_integer(capacity),
    do: "#{residents(count)}, room for #{RescordWeb.Locale.number(capacity)}"

  def occupancy(%{count: count}), do: residents(count)

  defp residents(count), do: RescordWeb.Locale.count(count, "resident", "residents")
  @doc "The form that puts a resident or a group in a location."
  attr :place_form, :any, required: true
  attr :residents, :any, required: true
  attr :groups, :any, required: true

  def placement_form(assigns) do
    ~H"""
    <details id="put-here">
      <summary><.icon name="plus" /> Put a resident or a group here</summary>
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
    """
  end

  @doc "The residents and the groups that live in a location, with their placements."
  attr :node, :any, required: true
  attr :organisation, :any, required: true
  attr :role, :any, required: true
  attr :place_form, :any, required: true
  attr :residents, :any, required: true
  attr :groups, :any, required: true

  def who_lives_here(assigns) do
    ~H"""
    <section aria-labelledby="who-heading">
      <h2 id="who-heading">Who lives here</h2>
      <p :if={@node.residents == [] and @node.groups == []}>Nobody has a placement here.</p>
      <ul :if={@node.residents != [] or @node.groups != []}>
        <li :for={placement <- @node.residents}>
          <.link navigate={resident_path(@organisation, placement.resident_id)}>
            <.icon name={Icons.section(:residents)} /> {placement.resident.name || "No name yet"}
          </.link>
          <.button
            :if={can?(@role, :placement, :finish)}
            phx-click="finish"
            phx-value-id={placement.id}
            aria-label={"End the placement of #{placement.resident.name || "the resident with no name"}"}
          >
            <.icon name="no-symbol" /> End the placement
          </.button>
        </li>
        <li :for={{placement, group, members} <- @node.groups}>
          <.link navigate={group_path(@organisation, group.id)}>
            <.icon name={Icons.section(:groups)} /> {Residents.group_name(group)}
          </.link>
          <span>
            (here: {length(members)} of the {length(group.members)} in the group)
          </span>
          <.button
            :if={can?(@role, :placement, :finish)}
            phx-click="finish"
            phx-value-id={placement.id}
            aria-label={"End the placement of #{Residents.group_name(group)}"}
          >
            <.icon name="no-symbol" /> End the placement
          </.button>
        </li>
      </ul>

      <.placement_form
        :if={can?(@role, :placement, :place)}
        place_form={@place_form}
        residents={@residents}
        groups={@groups}
      />
    </section>
    """
  end

  @doc "The locations inside a location, as cards."
  attr :node, :any, required: true
  attr :organisation, :any, required: true

  def inside(assigns) do
    ~H"""
    <section aria-labelledby="inside-heading">
      <h2 id="inside-heading">Inside</h2>
      <div data-places>
        <.place
          :for={child <- @node.children}
          node={child}
          organisation={@organisation}
          level={3}
        />
      </div>
    </section>
    """
  end

  @doc "The form that changes the name, the kind and the capacity of a location."
  attr :form, :any, required: true
  attr :kinds, :any, required: true

  def location_form(assigns) do
    ~H"""
    <details id="change-location">
      <summary><.icon name="pencil" /> Change the location</summary>
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
    """
  end

  @doc "The form that puts a location inside another."
  attr :move_form, :any, required: true
  attr :places, :any, required: true

  def move_location_form(assigns) do
    ~H"""
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
    """
  end

  @doc "The closing of a location."

  def close_location(assigns) do
    ~H"""
    <details id="close-location">
      <summary><.icon name="no-symbol" /> Close this location</summary>
      <p>Close a location that the organisation uses no more. Its history stays.</p>
      <.button phx-click="close">Close the location</.button>
    </details>
    """
  end

  @doc "The forms that change a location, move it and close it."
  attr :form, :any, required: true
  attr :kinds, :any, required: true
  attr :move_form, :any, required: true
  attr :places, :any, required: true

  def change_location(assigns) do
    ~H"""
    <section aria-labelledby="change-heading">
      <h2 id="change-heading">Change</h2>
      <.location_form form={@form} kinds={@kinds} />
      <.move_location_form move_form={@move_form} places={@places} />
      <.close_location />
    </section>
    """
  end

  def can?(role, subject, action), do: Locations.role_can?(role, subject, action)

  def resident_path(organisation, id), do: ~p"/o/#{organisation.short_name}/residents/#{id}"

  def group_path(organisation, id), do: ~p"/o/#{organisation.short_name}/groups/#{id}"
end
