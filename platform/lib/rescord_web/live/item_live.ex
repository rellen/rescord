defmodule RescordWeb.ItemLive do
  @moduledoc """
  One item of the inventory, at `/o/<short name>/inventory/<id>`: its lots
  with their levels in each place, and what happened to its stock
  (ADR 0034).

  A member records a delivery, a use, a move, a discard and a count here.
  An administrator changes the item, gives it a reorder level in a
  location, and removes it.

  The page opens again after a write, so each form is empty and each number
  is read again. It reads only the fields that it knows from what the
  browser sends, and makes no atom from it.

  The page shows what another person changed in the inventory or the
  locations, without a reload, and leaves its forms as they are
  (ADR 0096).
  """

  use RescordWeb, :live_view

  alias Rescord.{Accounts, Inventory, Lists, Locations}
  import RescordWeb.InventoryComponents

  alias RescordWeb.InventoryWords

  # The name of each form in the fields that the browser sends, and its assign.
  @forms [
    receive: :receive_form,
    use: :use_form,
    move: :move_form,
    discard: :discard_form,
    count: :count_form,
    item: :item_form,
    reorder: :reorder_form
  ]

  # The events that take stock out, each with its form and its action.
  @out %{
    "use" => {:use, :use_stock},
    "discard" => {:discard, :discard_stock},
    "move" => {:move, :move_stock}
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Listen first, and then read: no change falls between the two.
    socket = LiveChanges.listen(socket, [Inventory, Locations], &read_again/1)
    options = options(socket)
    role = socket.assigns.role

    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = stock} <- Inventory.item_stock(id, options) do
      can_revise? = Inventory.role_can?(role, :item, :revise)

      {:ok,
       socket
       |> assign(
         problems: [],
         refused: nil,
         members: Accounts.labels(options),
         can_record?: Inventory.role_can?(role, :movement, :use),
         can_revise?: can_revise?,
         can_remove?: Inventory.role_can?(role, :item, :remove),
         can_set_level?: Inventory.role_can?(role, :reorder_level, :set)
       )
       |> assign_stock(stock)
       |> assign_lists(can_revise?, options)
       |> assign_forms()}
    else
      _nothing ->
        {:ok,
         socket
         |> put_flash(:error, "That item is not in the inventory.")
         |> push_navigate(to: inventory_path(socket))}
    end
  end

  # What the page shows of the stock of the item, and of the places and the
  # suppliers that its forms offer. The history reads as of the instant of
  # `:as_of` (ADR 0096, "With Cinder"): a query of a temporal resource holds
  # the instant at which it was built, so each read here gives the history
  # a new instant, and Cinder reads it again.
  defp assign_stock(socket, stock) do
    options = options(socket)
    id = stock.item.id
    {:ok, tree} = Locations.tree(options)
    {:ok, suppliers} = Inventory.suppliers(options)
    {:ok, wanted} = Inventory.reorder_levels(options)

    places =
      for {node, depth} <- Locations.flat(tree),
          do: {String.duplicate("– ", depth) <> node.location.name, node.location.id}

    assign(socket,
      page_title: stock.item.name,
      as_of: DateTime.utc_now(),
      stock: stock,
      item: stock.item,
      places: places,
      place_names: Map.new(places, fn {name, id} -> {id, String.trim_leading(name, "– ")} end),
      suppliers: suppliers |> Enum.map(&{&1.name, &1.id}) |> Enum.sort(),
      wanted: Enum.filter(wanted, &(&1.item_id == id))
    )
  end

  # Another person changed the inventory or the locations (ADR 0096). The
  # forms stay as they are, with what the person typed. An item that another
  # person removed is not there to show. A page that found no item at the
  # mount goes to the inventory, and has nothing to read.
  defp read_again(%{assigns: %{item: item}} = socket) do
    case Inventory.item_stock(item.id, options(socket)) do
      {:ok, %{} = stock} ->
        assign_stock(socket, stock)

      {:ok, nil} ->
        socket
        |> put_flash(:info, "#{item.name} is not in the inventory now.")
        |> push_navigate(to: inventory_path(socket))

      {:error, _error} ->
        socket
    end
  end

  defp read_again(socket), do: socket

  defp assign_lists(socket, true, options) do
    {:ok, categories} = Lists.offered_values(:item_category, options)
    {:ok, units} = Lists.offered_values(:unit, options)
    choices = fn values -> Enum.map(values, &{to_string(&1.label), &1.id}) end

    assign(socket, categories: choices.(categories), units: choices.(units))
  end

  defp assign_lists(socket, _cannot, _options), do: assign(socket, categories: [], units: [])

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp inventory_path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/inventory"

  defp path(socket),
    do: ~p"/o/#{socket.assigns.organisation.short_name}/inventory/#{socket.assigns.item.id}"

  # Each form of the page. `filled` has the fields of the form that a member
  # sent, when the action refused them.
  defp assign_forms(socket, filled \\ %{}) do
    item = socket.assigns.item

    start = %{
      item:
        Map.merge(
          %{
            "name" => item.name,
            "category_id" => item.category_id,
            "unit_id" => item.unit_id,
            "reorder_level" => item.reorder_level && InventoryWords.plain(item.reorder_level),
            "note" => item.note
          },
          strength_fields(item)
        )
    }

    Enum.reduce(@forms, socket, fn {name, key}, socket ->
      fields = Map.get(filled, name) || Map.get(start, name, %{})
      assign(socket, key, typed_form(fields, as: name))
    end)
  end

  # A source of a form as the lot and the place of a movement.
  defp source(value) when is_binary(value) do
    case String.split(value, "|", parts: 2) do
      [lot_id, place] when lot_id != "" -> %{lot_id: lot_id, location_id: non_blank(place)}
      _other -> %{lot_id: nil, location_id: nil}
    end
  end

  defp source(_other), do: %{lot_id: nil, location_id: nil}

  # Runs a movement of a lot of this item. A lot of another item is refused:
  # the browser can send any id, and this page is about one item.
  defp of_this_item(socket, %{lot_id: lot_id} = movement, write) do
    if Enum.any?(socket.assigns.stock.lots, &(&1.lot.id == lot_id)),
      do: write.(movement),
      else: {:error, "Choose a lot of #{socket.assigns.item.name}"}
  end

  @impl true
  def handle_event("receive", %{"receive" => fields}, socket) when is_map(fields) do
    common = fn instant ->
      %{
        quantity: non_blank(fields["quantity"]),
        location_id: non_blank(fields["location_id"]),
        happened_at: instant
      }
    end

    write(socket, :receive, fields, fn instant, options ->
      case non_blank(fields["lot_id"]) do
        nil ->
          instant
          |> common.()
          |> Map.merge(%{
            item_id: socket.assigns.item.id,
            code: non_blank(fields["code"]),
            expires_on: non_blank(fields["expires_on"]),
            supplier_id: non_blank(fields["supplier_id"])
          })
          |> Inventory.receive_lot(options)

        lot_id ->
          of_this_item(
            socket,
            instant |> common.() |> Map.put(:lot_id, lot_id),
            &Inventory.receive_stock(&1, options)
          )
      end
    end)
  end

  # A use, a discard and a move take stock out of a lot in a place.
  def handle_event(event, params, socket) when is_map_key(@out, event) do
    {form, action} = Map.fetch!(@out, event)

    case params[event] do
      fields when is_map(fields) ->
        write(socket, form, fields, fn instant, options ->
          movement =
            fields["source"]
            |> source()
            |> Map.merge(%{
              quantity: non_blank(fields["quantity"]),
              note: non_blank(fields["note"]),
              happened_at: instant
            })

          # A move also names the place that the stock goes to.
          movement =
            if form == :move,
              do: Map.put(movement, :to_location_id, non_blank(fields["to_location_id"])),
              else: movement

          of_this_item(socket, movement, &apply(Inventory, action, [&1, options]))
        end)

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("count", %{"count" => fields}, socket) when is_map(fields) do
    write(socket, :count, fields, fn instant, options ->
      of_this_item(
        socket,
        %{
          lot_id: non_blank(fields["lot_id"]),
          location_id: non_blank(fields["location_id"]),
          counted: non_blank(fields["counted"]),
          note: non_blank(fields["note"]),
          happened_at: instant
        },
        &Inventory.count_stock(&1, options)
      )
    end)
  end

  def handle_event("revise", %{"item" => fields}, socket) when is_map(fields) do
    item = socket.assigns.item

    attributes = %{
      name: non_blank(fields["name"]),
      category_id: non_blank(fields["category_id"]),
      unit_id: non_blank(fields["unit_id"]),
      reorder_level: non_blank(fields["reorder_level"]),
      note: non_blank(fields["note"])
    }

    write(socket, :item, fields, fn _instant, options ->
      with {:ok, strength} <- read_strength(fields) do
        # A strength that the form cannot show stays when the form sends
        # none: the person did not see it, so the person did not remove it.
        kept? = is_nil(strength) and item.strength != nil and strength_fields(item) == %{}
        attributes = if kept?, do: attributes, else: Map.put(attributes, :strength, strength)

        Inventory.revise_item(item, attributes, options)
      end
    end)
  end

  def handle_event("set_level", %{"reorder" => fields}, socket) when is_map(fields) do
    write(socket, :reorder, fields, fn _instant, options ->
      case non_blank(fields["location_id"]) do
        nil ->
          {:error, "Choose the location of the reorder level"}

        location_id ->
          Inventory.set_reorder_level(
            socket.assigns.item.id,
            location_id,
            non_blank(fields["quantity"]),
            options
          )
      end
    end)
  end

  def handle_event("remove", _params, socket) do
    case Inventory.remove_item(socket.assigns.item, options(socket)) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "#{socket.assigns.item.name} is not in the inventory now.")
         |> push_navigate(to: inventory_path(socket))}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error), refused: nil)}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Runs the action of a form. The time of the form is a local time of the
  # organisation, and is never after now.
  defp write(socket, form, fields, action) do
    with {:ok, instant} <- Accounts.instant(socket.assigns.organisation, fields["at"]),
         {:ok, _record} <- action.(instant, options(socket)) do
      {:noreply, push_navigate(socket, to: path(socket))}
    else
      {:error, words} when is_binary(words) ->
        {:noreply, refuse(socket, form, fields, [words])}

      {:error, error} ->
        {:noreply, refuse(socket, form, fields, Accounts.error_messages(error))}
    end
  end

  # The problems are beside the form that the person sent. A person can send
  # the event of a form that the page did not draw for them: the problems
  # are then below the header.
  defp refuse(socket, form, fields, problems) do
    socket
    |> assign(problems: problems, refused: if(drawn?(socket.assigns, form), do: form))
    |> assign_forms(%{form => fields})
  end

  defp drawn?(assigns, :receive), do: assigns.can_record?

  defp drawn?(assigns, form) when form in [:use, :move, :discard],
    do: assigns.can_record? and in_stock(assigns.stock) != []

  defp drawn?(assigns, :count), do: assigns.can_record? and assigns.stock.lots != []
  defp drawn?(assigns, :item), do: assigns.can_revise?
  defp drawn?(assigns, :reorder), do: assigns.can_set_level?

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        sources: sources(assigns.stock, assigns.place_names),
        lot_choices: lot_choices(assigns.stock)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      section={:inventory}
    >
      <.header>
        {@item.name}
        <:subtitle>
          {(@item.category && @item.category.label) || "An item of the inventory"}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/inventory"} data-variant="secondary">
            <.icon name="archive-box" /> The inventory
          </.link>
        </:actions>
      </.header>

      <.problems :if={is_nil(@refused)} list={@problems} />

      <.item_stock
        stock={@stock}
        item={@item}
        place_names={@place_names}
        organisation={@organisation}
      />

      <.record_stock
        :if={@can_record?}
        item={@item}
        places={@places}
        suppliers={@suppliers}
        sources={@sources}
        lot_choices={@lot_choices}
        receive_form={@receive_form}
        use_form={@use_form}
        move_form={@move_form}
        discard_form={@discard_form}
        count_form={@count_form}
        refused={@refused}
        problems={@problems}
      />

      <.stock_history
        as_of={@as_of}
        lots={@lot_choices}
        item={@item}
        organisation={@organisation}
        members={@members}
        user={@current_user}
        place_names={@place_names}
      />

      <.keep_item
        :if={@can_revise? or @can_set_level?}
        can_revise?={@can_revise?}
        can_set_level?={@can_set_level?}
        can_remove?={@can_remove?}
        item={@item}
        item_form={@item_form}
        reorder_form={@reorder_form}
        categories={@categories}
        units={@units}
        wanted={@wanted}
        places={@places}
        place_names={@place_names}
        refused={@refused}
        problems={@problems}
      />
    </Layouts.app>
    """
  end
end
