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
  """

  use RescordWeb, :live_view

  alias Rescord.{Accounts, Inventory, Lists, Locations}
  alias RescordWeb.{InventoryWords, ResidentWords, TaskWords}

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

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = options(socket)
    role = socket.assigns.role

    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = stock} <- Inventory.item_stock(id, options) do
      {:ok, history} = Inventory.history(id, options)
      {:ok, tree} = Locations.tree(options)
      {:ok, suppliers} = Inventory.suppliers(options)
      {:ok, wanted} = Inventory.reorder_levels(options)
      {:ok, members} = Accounts.members([load: [:email]] ++ options)
      can_revise? = Inventory.role_can?(role, :item, :revise)

      places =
        for {node, depth} <- Locations.flat(tree),
            do: {String.duplicate("– ", depth) <> node.location.name, node.location.id}

      {:ok,
       socket
       |> assign(
         page_title: stock.item.name,
         problems: [],
         refused: nil,
         stock: stock,
         item: stock.item,
         history: history,
         places: places,
         place_names: Map.new(places, fn {name, id} -> {id, String.trim_leading(name, "– ")} end),
         suppliers: suppliers |> Enum.map(&{&1.name, &1.id}) |> Enum.sort(),
         wanted: Enum.filter(wanted, &(&1.item_id == id)),
         members: Map.new(members, &{&1.user_id, to_string(&1.email)}),
         can_record?: Inventory.role_can?(role, :movement, :use),
         can_revise?: can_revise?,
         can_remove?: Inventory.role_can?(role, :item, :remove),
         can_set_level?: Inventory.role_can?(role, :reorder_level, :set)
       )
       |> assign_lists(can_revise?, options)
       |> assign_forms()}
    else
      _nothing ->
        {:ok,
         socket
         |> put_flash(:error, "That item is not in the inventory.")
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/inventory")}
    end
  end

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

  defp path(socket),
    do: ~p"/o/#{socket.assigns.organisation.short_name}/inventory/#{socket.assigns.item.id}"

  # Each form of the page. `filled` has the fields of the form that a member
  # sent, when the action refused them.
  defp assign_forms(socket, filled \\ %{}) do
    item = socket.assigns.item

    start = %{
      item: %{
        "name" => item.name,
        "category_id" => item.category_id,
        "unit_id" => item.unit_id,
        "reorder_level" => item.reorder_level && InventoryWords.plain(item.reorder_level),
        "note" => item.note
      }
    }

    Enum.reduce(@forms, socket, fn {name, key}, socket ->
      fields = Map.get(filled, name) || Map.get(start, name, %{})
      assign(socket, key, to_form(fields, as: name))
    end)
  end

  # The stock of the page as the choices of a select: each lot in each place
  # where it has some. The value is the id of the lot, a bar, and the id of
  # the location or nothing.
  defp sources(stock, place_names) do
    for %{lot: lot, places: places} <- stock.lots, {place, level} <- places do
      {"#{InventoryWords.lot(lot)}, #{place_words(place, place_names)}: " <>
         InventoryWords.quantity(level, stock.item), "#{lot.id}|#{place}"}
    end
  end

  # A source of a form as the lot and the place of a movement.
  defp source(value) when is_binary(value) do
    case String.split(value, "|", parts: 2) do
      [lot_id, place] when lot_id != "" -> %{lot_id: lot_id, location_id: text(place)}
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
        quantity: text(fields["quantity"]),
        location_id: text(fields["location_id"]),
        happened_at: instant
      }
    end

    write(socket, :receive, fields, fn instant, options ->
      case text(fields["lot_id"]) do
        nil ->
          instant
          |> common.()
          |> Map.merge(%{
            item_id: socket.assigns.item.id,
            code: text(fields["code"]),
            expires_on: text(fields["expires_on"]),
            supplier_id: text(fields["supplier_id"])
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

  def handle_event("use", %{"use" => fields}, socket) when is_map(fields) do
    write(socket, :use, fields, fn instant, options ->
      movement =
        fields["source"]
        |> source()
        |> Map.merge(%{
          quantity: text(fields["quantity"]),
          note: text(fields["note"]),
          happened_at: instant
        })

      of_this_item(socket, movement, &Inventory.use_stock(&1, options))
    end)
  end

  def handle_event("discard", %{"discard" => fields}, socket) when is_map(fields) do
    write(socket, :discard, fields, fn instant, options ->
      movement =
        fields["source"]
        |> source()
        |> Map.merge(%{
          quantity: text(fields["quantity"]),
          note: text(fields["note"]),
          happened_at: instant
        })

      of_this_item(socket, movement, &Inventory.discard_stock(&1, options))
    end)
  end

  def handle_event("move", %{"move" => fields}, socket) when is_map(fields) do
    write(socket, :move, fields, fn instant, options ->
      movement =
        fields["source"]
        |> source()
        |> Map.merge(%{
          to_location_id: text(fields["to_location_id"]),
          quantity: text(fields["quantity"]),
          note: text(fields["note"]),
          happened_at: instant
        })

      of_this_item(socket, movement, &Inventory.move_stock(&1, options))
    end)
  end

  def handle_event("count", %{"count" => fields}, socket) when is_map(fields) do
    write(socket, :count, fields, fn instant, options ->
      of_this_item(
        socket,
        %{
          lot_id: text(fields["lot_id"]),
          location_id: text(fields["location_id"]),
          counted: text(fields["counted"]),
          note: text(fields["note"]),
          happened_at: instant
        },
        &Inventory.count_stock(&1, options)
      )
    end)
  end

  def handle_event("revise", %{"item" => fields}, socket) when is_map(fields) do
    write(socket, :item, fields, fn _instant, options ->
      Inventory.revise_item(
        socket.assigns.item,
        %{
          name: text(fields["name"]),
          category_id: text(fields["category_id"]),
          unit_id: text(fields["unit_id"]),
          reorder_level: text(fields["reorder_level"]),
          note: text(fields["note"])
        },
        options
      )
    end)
  end

  def handle_event("set_level", %{"reorder" => fields}, socket) when is_map(fields) do
    write(socket, :reorder, fields, fn _instant, options ->
      case text(fields["location_id"]) do
        nil ->
          {:error, "Choose the location of the reorder level"}

        location_id ->
          Inventory.set_reorder_level(
            socket.assigns.item.id,
            location_id,
            text(fields["quantity"]),
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
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/inventory")}

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

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  defp place_words(nil, _names), do: "no place in particular"
  defp place_words("", _names), do: "no place in particular"
  defp place_words(id, names), do: Map.get(names, id, "a location that is not here now")

  defp when_words(instant, organisation) do
    local = Accounts.local_time(organisation, instant)
    "#{ResidentWords.date(DateTime.to_date(local))}, #{TaskWords.time(local)}"
  end

  # The address of the member who recorded a movement. A root user is not a
  # member, and reads their own movements as their own.
  defp author(members, movement, user) do
    cond do
      Map.has_key?(members, movement.author_id) -> members[movement.author_id]
      movement.author_id == user.id -> to_string(user.email)
      true -> "A person who is not a member now"
    end
  end

  defp in_stock(stock), do: Enum.filter(stock.lots, &(&1.places != []))
  defp empty(stock), do: Enum.filter(stock.lots, &(&1.places == []))

  defp lot_choices(stock), do: Enum.map(stock.lots, &{lot_words(&1.lot), &1.lot.id})

  defp lot_words(%{expires_on: nil} = lot), do: InventoryWords.lot(lot)

  defp lot_words(lot),
    do: "#{InventoryWords.lot(lot)}, expires #{ResidentWords.date(lot.expires_on)}"

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        sources: sources(assigns.stock, assigns.place_names),
        lot_choices: lot_choices(assigns.stock)
      )

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        {@item.name}
        <:subtitle>
          {(@item.category && @item.category.label) || "An item of the inventory"}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/inventory"} data-variant="secondary">
            The inventory
          </.link>
        </:actions>
      </.header>

      <.problems :if={is_nil(@refused)} list={@problems} />

      <section aria-labelledby="stock-heading">
        <h2 id="stock-heading">Stock</h2>
        <.list>
          <:item title="In stock">{InventoryWords.quantity(@stock.level, @item)}</:item>
          <:item title="State">
            <.state :for={{words, kind} <- InventoryWords.states(@stock)} kind={kind}>
              {words}
            </.state>
          </:item>
          <:item :if={@item.reorder_level} title="Order more when the stock is below">
            {InventoryWords.quantity(@item.reorder_level, @item)}
          </:item>
          <:item :if={@item.note} title="Note">{@item.note}</:item>
        </.list>

        <ul :if={@stock.short != []} id="short">
          <li :for={short <- @stock.short}>
            {short_words(short, @item, @place_names)}
          </li>
        </ul>

        <p :if={in_stock(@stock) == []}>There is no stock of this item.</p>
        <div :if={in_stock(@stock) != []} data-scroll>
          <table id="lots">
            <thead>
              <tr>
                <th scope="col">Lot</th>
                <th scope="col">Expiry</th>
                <th scope="col">Where</th>
                <th scope="col">In the lot</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={lot_stock <- in_stock(@stock)} id={"lot-#{lot_stock.lot.id}"}>
                <td>
                  {InventoryWords.lot(lot_stock.lot)}
                  <small :if={lot_stock.lot.supplier}>From {lot_stock.lot.supplier.name}</small>
                  <small :if={lot_stock.lot.note}>{lot_stock.lot.note}</small>
                </td>
                <td>
                  <.state kind={InventoryWords.expiry_kind(lot_stock.expiry)}>
                    {InventoryWords.expiry(lot_stock.expiry)}
                  </.state>
                  <small :if={lot_stock.lot.expires_on}>
                    {ResidentWords.date(lot_stock.lot.expires_on)}
                  </small>
                </td>
                <td>
                  <ul>
                    <li :for={{place, level} <- lot_stock.places}>
                      {String.capitalize(place_words(place, @place_names))}: {InventoryWords.quantity(
                        level,
                        @item
                      )}
                    </li>
                  </ul>
                </td>
                <td>{InventoryWords.quantity(lot_stock.level, @item)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <details :if={empty(@stock) != []} id="empty-lots">
          <summary>Lots with nothing left ({length(empty(@stock))})</summary>
          <ul>
            <li :for={lot_stock <- empty(@stock)}>{lot_words(lot_stock.lot)}</li>
          </ul>
        </details>
      </section>

      <section :if={@can_record?} aria-labelledby="record-heading">
        <h2 id="record-heading">Record what happened</h2>

        <details id="receive">
          <summary>Stock came in</summary>
          <.problems :if={@refused == :receive} list={@problems} />
          <.form for={@receive_form} id="receive-form" phx-submit="receive">
            <.input
              field={@receive_form[:lot_id]}
              type="select"
              label="Lot"
              prompt="A new lot"
              options={@lot_choices}
            />
            <.input
              field={@receive_form[:code]}
              type="text"
              label="Code on the pack of a new lot, if it has one"
              maxlength="60"
            />
            <.input
              field={@receive_form[:expires_on]}
              type="date"
              label="Expiry date of a new lot, if it has one"
            />
            <.input
              field={@receive_form[:supplier_id]}
              type="select"
              label="Supplier of a new lot"
              prompt="Not recorded"
              options={@suppliers}
            />
            <.input
              field={@receive_form[:quantity]}
              type="number"
              label={quantity_label("How much came in", @item)}
              min="0"
              step="any"
              required
            />
            <.input
              field={@receive_form[:location_id]}
              type="select"
              label="Where it is now"
              prompt="No place in particular"
              options={@places}
            />
            <.input
              field={@receive_form[:at]}
              type="datetime-local"
              label="When it came in, if not now"
            />
            <footer><.button type="submit">Record the stock</.button></footer>
          </.form>
        </details>

        <details :if={@sources != []} id="use">
          <summary>Stock was used</summary>
          <.problems :if={@refused == :use} list={@problems} />
          <.form for={@use_form} id="use-form" phx-submit="use">
            <.input
              field={@use_form[:source]}
              type="select"
              label="From which lot and place"
              options={@sources}
            />
            <.input
              field={@use_form[:quantity]}
              type="number"
              label={quantity_label("How much was used", @item)}
              min="0"
              step="any"
              required
            />
            <.input field={@use_form[:note]} type="text" label="Note" maxlength="500" />
            <.input field={@use_form[:at]} type="datetime-local" label="When, if not now" />
            <footer><.button type="submit">Record the use</.button></footer>
          </.form>
        </details>

        <details :if={@sources != []} id="move">
          <summary>Stock moved to another place</summary>
          <.problems :if={@refused == :move} list={@problems} />
          <.form for={@move_form} id="move-form" phx-submit="move">
            <.input
              field={@move_form[:source]}
              type="select"
              label="From which lot and place"
              options={@sources}
            />
            <.input
              field={@move_form[:to_location_id]}
              type="select"
              label="To which place"
              prompt="No place in particular"
              options={@places}
            />
            <.input
              field={@move_form[:quantity]}
              type="number"
              label={quantity_label("How much moved", @item)}
              min="0"
              step="any"
              required
            />
            <.input field={@move_form[:note]} type="text" label="Note" maxlength="500" />
            <.input field={@move_form[:at]} type="datetime-local" label="When, if not now" />
            <footer><.button type="submit">Record the move</.button></footer>
          </.form>
        </details>

        <details :if={@sources != []} id="discard">
          <summary>Stock was thrown out</summary>
          <.problems :if={@refused == :discard} list={@problems} />
          <.form for={@discard_form} id="discard-form" phx-submit="discard">
            <.input
              field={@discard_form[:source]}
              type="select"
              label="From which lot and place"
              options={@sources}
            />
            <.input
              field={@discard_form[:quantity]}
              type="number"
              label={quantity_label("How much was thrown out", @item)}
              min="0"
              step="any"
              required
            />
            <.input field={@discard_form[:note]} type="text" label="Why" maxlength="500" />
            <.input field={@discard_form[:at]} type="datetime-local" label="When, if not now" />
            <footer><.button type="submit">Record the discard</.button></footer>
          </.form>
        </details>

        <details :if={@lot_choices != []} id="count">
          <summary>I counted the stock</summary>
          <.problems :if={@refused == :count} list={@problems} />
          <p>
            Give the number that is there. Rescord records the difference from its own number.
          </p>
          <.form for={@count_form} id="count-form" phx-submit="count">
            <.input field={@count_form[:lot_id]} type="select" label="Lot" options={@lot_choices} />
            <.input
              field={@count_form[:location_id]}
              type="select"
              label="Place"
              prompt="No place in particular"
              options={@places}
            />
            <.input
              field={@count_form[:counted]}
              type="number"
              label={quantity_label("How much is there", @item)}
              min="0"
              step="any"
              required
            />
            <.input field={@count_form[:note]} type="text" label="Note" maxlength="500" />
            <footer><.button type="submit">Record the count</.button></footer>
          </.form>
        </details>
      </section>

      <section aria-labelledby="history-heading">
        <h2 id="history-heading">What happened</h2>
        <p :if={@history == []}>Nothing happened to the stock of this item yet.</p>
        <div :if={@history != []} data-scroll>
          <table id="history">
            <thead>
              <tr>
                <th scope="col">When</th>
                <th scope="col">What</th>
                <th scope="col">Change</th>
                <th scope="col">Lot</th>
                <th scope="col">Where</th>
                <th scope="col">Who</th>
                <th scope="col">Note</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={movement <- @history} id={"movement-#{movement.id}"}>
                <td>{when_words(movement.happened_at, @organisation)}</td>
                <td>{InventoryWords.movement(movement)}</td>
                <td>{InventoryWords.change(movement.quantity)}</td>
                <td>{InventoryWords.lot(movement.lot)}</td>
                <td>{String.capitalize(place_words(movement.location_id, @place_names))}</td>
                <td>{author(@members, movement, @current_user)}</td>
                <td>{movement.note}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section :if={@can_revise? or @can_set_level?} aria-labelledby="keep-heading">
        <h2 id="keep-heading">Keep the item</h2>

        <details :if={@can_revise?} id="edit-item">
          <summary>Change the item</summary>
          <.problems :if={@refused == :item} list={@problems} />
          <.form for={@item_form} id="item-form" phx-submit="revise">
            <.input field={@item_form[:name]} type="text" label="Name" maxlength="80" required />
            <.input
              field={@item_form[:category_id]}
              type="select"
              label="Category"
              prompt="Not recorded"
              options={@categories}
            />
            <.input
              field={@item_form[:unit_id]}
              type="select"
              label="Unit that you count it in"
              prompt="Not recorded"
              options={@units}
            />
            <.input
              field={@item_form[:reorder_level]}
              type="number"
              label="Order more when the stock is below, if you give a number"
              min="0"
              step="any"
            />
            <.input field={@item_form[:note]} type="text" label="Note" maxlength="1000" />
            <footer><.button type="submit">Save the item</.button></footer>
          </.form>
        </details>

        <details :if={@can_set_level?} id="reorder">
          <summary>Reorder levels in a location ({length(@wanted)})</summary>
          <.problems :if={@refused == :reorder} list={@problems} />
          <ul :if={@wanted != []} id="wanted">
            <li :for={level <- @wanted}>
              {String.capitalize(place_words(level.location_id, @place_names))}: bring more when
              the stock there is below {InventoryWords.quantity(level.quantity, @item)}
            </li>
          </ul>
          <.form for={@reorder_form} id="reorder-form" phx-submit="set_level">
            <.input
              field={@reorder_form[:location_id]}
              type="select"
              label="Location"
              prompt="Choose a location"
              options={@places}
              required
            />
            <.input
              field={@reorder_form[:quantity]}
              type="number"
              label="Bring more when the stock there is below. No number removes the level"
              min="0"
              step="any"
            />
            <footer><.button type="submit">Save the level</.button></footer>
          </.form>
        </details>

        <details :if={@can_remove?} id="remove-item">
          <summary>Remove the item</summary>
          <p>
            The item leaves the inventory. Its lots and what happened to its stock stay in the
            history.
          </p>
          <.button phx-click="remove">Remove {@item.name}</.button>
        </details>
      </section>
    </Layouts.app>
    """
  end

  defp quantity_label(words, item) do
    case InventoryWords.unit(item) do
      nil -> words
      unit -> "#{words}, in #{unit}"
    end
  end

  defp short_words(%{location_id: nil} = short, item, _names) do
    "Order more: #{InventoryWords.quantity(short.level, item)} is good to use, and the " <>
      "organisation wants #{InventoryWords.quantity(short.wanted, item)} or more."
  end

  defp short_words(short, item, names) do
    "#{String.capitalize(place_words(short.location_id, names))} has " <>
      "#{InventoryWords.quantity(short.level, item)} that is good to use, and wants " <>
      "#{InventoryWords.quantity(short.wanted, item)} or more."
  end
end
