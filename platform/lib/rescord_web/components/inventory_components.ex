defmodule RescordWeb.InventoryComponents do
  @moduledoc """
  The parts of the pages of the inventory (ADR 0034 and ADR 0037): the stock
  of an item, the forms that record what happened to it, its history, and
  the forms that keep it.

  A form says what an action refused in itself when `refused` names it, so
  a person reads the words beside what they typed.
  """

  use RescordWeb, :html

  import RescordWeb.ToolComponents, only: [strength_controls: 1]
  import Shoddy.Strings, only: [upcase_first: 1]

  alias Rescord.{Accounts, Dosage, Inventory}
  alias RescordWeb.{InventoryWords, ResidentWords, TaskWords, ToolWords}

  @doc "The stock of an item: its level, its state, and each lot in each place."
  attr :stock, :map, required: true
  attr :item, :map, required: true
  attr :place_names, :map, required: true
  attr :organisation, :map, required: true

  def item_stock(assigns) do
    ~H"""
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
        <:item :if={@item.strength} title="Strength">
          <span id="item-strength">{ToolWords.strength(@item.strength)}</span>
        </:item>
        <:item :if={@item.note} title="Note">{@item.note}</:item>
      </.list>

      <%!-- The dose calculator of the tools, with the strength of this item (ADR 0072). --%>
      <p :if={Dosage.strength?(@item.strength)}>
        <.link
          navigate={~p"/o/#{@organisation.short_name}/tools/dose?#{[item: @item.id]}"}
          data-variant="secondary"
        >
          Calculate a dose with this strength
        </.link>
      </p>

      <ul :if={@stock.below_zero != []} id="below-zero">
        <li :for={{lot, place, level} <- @stock.below_zero}>
          {InventoryWords.lot(lot)}, {place_words(place, @place_names)}: the record has {InventoryWords.quantity(
            level,
            @item
          )}. Count what is there, and record the count.
        </li>
      </ul>

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
              <td data-label="Expiry">
                <.state kind={InventoryWords.expiry_kind(lot_stock.expiry)}>
                  {InventoryWords.expiry(lot_stock.expiry)}
                </.state>
                <small :if={lot_stock.lot.expires_on}>
                  {ResidentWords.date(lot_stock.lot.expires_on)}
                </small>
              </td>
              <td data-label="Where">
                <ul>
                  <li :for={{place, level} <- lot_stock.places}>
                    {upcase_first(place_words(place, @place_names))}: {InventoryWords.quantity(
                      level,
                      @item
                    )}
                  </li>
                </ul>
              </td>
              <td data-label="In the lot">{InventoryWords.quantity(lot_stock.level, @item)}</td>
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
    """
  end

  @doc "The forms that record what happened to the stock of an item."
  attr :item, :map, required: true
  attr :places, :list, required: true
  attr :suppliers, :list, required: true
  attr :sources, :list, required: true
  attr :lot_choices, :list, required: true
  attr :receive_form, :any, required: true
  attr :use_form, :any, required: true
  attr :move_form, :any, required: true
  attr :discard_form, :any, required: true
  attr :count_form, :any, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def record_stock(assigns) do
    ~H"""
    <section aria-labelledby="record-heading">
      <h2 id="record-heading">Record what happened</h2>

      <.receive_form
        form={@receive_form}
        item={@item}
        lots={@lot_choices}
        suppliers={@suppliers}
        places={@places}
        refused={@refused}
        problems={@problems}
      />

      <.use_form
        :if={@sources != []}
        form={@use_form}
        item={@item}
        sources={@sources}
        refused={@refused}
        problems={@problems}
      />

      <.move_form
        :if={@sources != []}
        form={@move_form}
        item={@item}
        sources={@sources}
        places={@places}
        refused={@refused}
        problems={@problems}
      />

      <.discard_form
        :if={@sources != []}
        form={@discard_form}
        item={@item}
        sources={@sources}
        refused={@refused}
        problems={@problems}
      />

      <.count_form
        :if={@lot_choices != []}
        form={@count_form}
        item={@item}
        lots={@lot_choices}
        places={@places}
        refused={@refused}
        problems={@problems}
      />
    </section>
    """
  end

  @doc "The form of stock that came in: to a new lot, or to a lot that is there."
  attr :form, :any, required: true
  attr :item, :map, required: true
  attr :lots, :list, required: true
  attr :suppliers, :list, required: true
  attr :places, :list, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def receive_form(assigns) do
    ~H"""
    <details id="receive">
      <summary>Stock came in</summary>
      <.problems :if={@refused == :receive} list={@problems} />
      <.form for={@form} id="receive-form" phx-submit="receive">
        <.input
          field={@form[:lot_id]}
          type="select"
          label="Lot"
          prompt="A new lot"
          options={@lots}
        />
        <.input
          field={@form[:code]}
          type="text"
          label="Code on the pack of a new lot, if it has one"
          maxlength="60"
        />
        <.input
          field={@form[:expires_on]}
          type="date"
          label="Expiry date of a new lot, if it has one"
        />
        <.input
          field={@form[:supplier_id]}
          type="select"
          label="Supplier of a new lot"
          prompt="Not recorded"
          options={@suppliers}
        />
        <.input
          field={@form[:quantity]}
          type="number"
          label={quantity_label("How much came in", @item)}
          min="0"
          step="any"
          required
        />
        <.input
          field={@form[:location_id]}
          type="select"
          label="Where it is now"
          prompt="No place in particular"
          options={@places}
        />
        <.input
          field={@form[:at]}
          type="datetime-local"
          label="When it came in, if not now"
        />
        <footer><.button type="submit">Record the stock</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form of stock that a member used."
  attr :form, :any, required: true
  attr :item, :map, required: true
  attr :sources, :list, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def use_form(assigns) do
    ~H"""
    <details id="use">
      <summary>Stock was used</summary>
      <.problems :if={@refused == :use} list={@problems} />
      <.form for={@form} id="use-form" phx-submit="use">
        <.input
          field={@form[:source]}
          type="select"
          label="From which lot and place"
          options={@sources}
        />
        <.input
          field={@form[:quantity]}
          type="number"
          label={quantity_label("How much was used", @item)}
          min="0"
          step="any"
          required
        />
        <.input field={@form[:note]} type="text" label="Note" maxlength="500" />
        <.input field={@form[:at]} type="datetime-local" label="When, if not now" />
        <footer><.button type="submit">Record the use</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form of stock that moved to another place."
  attr :form, :any, required: true
  attr :item, :map, required: true
  attr :sources, :list, required: true
  attr :places, :list, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def move_form(assigns) do
    ~H"""
    <details id="move">
      <summary>Stock moved to another place</summary>
      <.problems :if={@refused == :move} list={@problems} />
      <.form for={@form} id="move-form" phx-submit="move">
        <.input
          field={@form[:source]}
          type="select"
          label="From which lot and place"
          options={@sources}
        />
        <.input
          field={@form[:to_location_id]}
          type="select"
          label="To which place"
          prompt="No place in particular"
          options={@places}
        />
        <.input
          field={@form[:quantity]}
          type="number"
          label={quantity_label("How much moved", @item)}
          min="0"
          step="any"
          required
        />
        <.input field={@form[:note]} type="text" label="Note" maxlength="500" />
        <.input field={@form[:at]} type="datetime-local" label="When, if not now" />
        <footer><.button type="submit">Record the move</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form of stock that a member threw out."
  attr :form, :any, required: true
  attr :item, :map, required: true
  attr :sources, :list, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def discard_form(assigns) do
    ~H"""
    <details id="discard">
      <summary>Stock was thrown out</summary>
      <.problems :if={@refused == :discard} list={@problems} />
      <.form for={@form} id="discard-form" phx-submit="discard">
        <.input
          field={@form[:source]}
          type="select"
          label="From which lot and place"
          options={@sources}
        />
        <.input
          field={@form[:quantity]}
          type="number"
          label={quantity_label("How much was thrown out", @item)}
          min="0"
          step="any"
          required
        />
        <.input field={@form[:note]} type="text" label="Why" maxlength="500" />
        <.input field={@form[:at]} type="datetime-local" label="When, if not now" />
        <footer><.button type="submit">Record the discard</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The form of a count of a lot in a place."
  attr :form, :any, required: true
  attr :item, :map, required: true
  attr :lots, :list, required: true
  attr :places, :list, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def count_form(assigns) do
    ~H"""
    <details :if={@lots != []} id="count">
      <summary>I counted the stock</summary>
      <.problems :if={@refused == :count} list={@problems} />
      <p>
        Give the number that is there. Rescord records the difference from its own number.
      </p>
      <.form for={@form} id="count-form" phx-submit="count">
        <.input field={@form[:lot_id]} type="select" label="Lot" options={@lots} />
        <.input
          field={@form[:location_id]}
          type="select"
          label="Place"
          prompt="No place in particular"
          options={@places}
        />
        <.input
          field={@form[:counted]}
          type="number"
          label={quantity_label("How much is there", @item)}
          min="0"
          step="any"
          required
        />
        <.input field={@form[:note]} type="text" label="Note" maxlength="500" />
        <footer><.button type="submit">Record the count</.button></footer>
      </.form>
    </details>
    """
  end

  @doc """
  What happened to the stock of an item, the newest first: each movement,
  in pages, with a filter on the date, the kind and the lot (ADR 0084).
  """
  attr :item, :map, required: true
  attr :lots, :list, required: true, doc: "each lot of the item, as the choices of a filter"
  attr :organisation, :map, required: true
  attr :members, :map, required: true
  attr :user, :map, required: true
  attr :place_names, :map, required: true

  def stock_history(assigns) do
    ~H"""
    <section id="history" aria-labelledby="history-heading">
      <h2 id="history-heading">What happened</h2>
      <Cinder.collection
        id="history"
        query={Inventory.query_to_history(@item.id, actor: @user, tenant: @organisation)}
        actor={@user}
        tenant={@organisation}
        page_size={[default: 25, options: [25, 50, 100]]}
      >
        <:empty :let={found}>
          <p :if={found.filtered?}>No movement matches the filters.</p>
          <p :if={not found.filtered?}>Nothing happened to the stock of this item yet.</p>
        </:empty>
        <:col
          :let={movement}
          field="happened_at"
          label="When"
          sort={[cycle: [:desc, :asc]]}
          filter={[type: :date_range]}
        >
          {when_words(movement.happened_at, @organisation)}
        </:col>
        <:col
          :let={movement}
          field="kind"
          label="What"
          filter={[type: :select, prompt: "Any kind", options: InventoryWords.movement_options()]}
        >
          <span data-label="What">{InventoryWords.movement(movement)}</span>
        </:col>
        <:col :let={movement} field="quantity" label="Change">
          <span data-label="Change">{InventoryWords.change(movement.quantity)}</span>
        </:col>
        <:col
          :let={movement}
          field="lot_id"
          label="Lot"
          filter={[type: :select, prompt: "Any lot", options: @lots]}
        >
          <span data-label="Lot">{InventoryWords.lot(movement.lot)}</span>
        </:col>
        <:col :let={movement} field="location_id" label="Where">
          <span data-label="Where">
            {upcase_first(place_words(movement.location_id, @place_names))}
          </span>
        </:col>
        <:col :let={movement} field="author_id" label="Who">
          <span data-label="Who">{author(@members, movement, @user)}</span>
        </:col>
        <:col :let={movement} field="note" label="Note">
          <span :if={movement.note} data-label="Note">{movement.note}</span>
        </:col>
      </Cinder.collection>
    </section>
    """
  end

  @doc "The forms that keep an item: its facts, its reorder levels, and its removal."
  attr :can_revise?, :boolean, required: true
  attr :can_set_level?, :boolean, required: true
  attr :can_remove?, :boolean, required: true
  attr :item, :map, required: true
  attr :item_form, :any, required: true
  attr :reorder_form, :any, required: true
  attr :categories, :list, required: true
  attr :units, :list, required: true
  attr :wanted, :list, required: true
  attr :places, :list, required: true
  attr :place_names, :map, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def keep_item(assigns) do
    ~H"""
    <section aria-labelledby="keep-heading">
      <h2 id="keep-heading">Keep the item</h2>

      <.item_form
        :if={@can_revise?}
        form={@item_form}
        categories={@categories}
        units={@units}
        refused={@refused}
        problems={@problems}
      />

      <.reorder_form
        :if={@can_set_level?}
        form={@reorder_form}
        item={@item}
        wanted={@wanted}
        places={@places}
        place_names={@place_names}
        refused={@refused}
        problems={@problems}
      />

      <.remove_item :if={@can_remove?} item={@item} />
    </section>
    """
  end

  @doc "The form that changes the facts of an item."
  attr :form, :any, required: true
  attr :categories, :list, required: true
  attr :units, :list, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def item_form(assigns) do
    ~H"""
    <details id="edit-item">
      <summary>Change the item</summary>
      <.problems :if={@refused == :item} list={@problems} />
      <.form for={@form} id="item-form" phx-submit="revise">
        <.input field={@form[:name]} type="text" label="Name" maxlength="80" required />
        <.input
          field={@form[:category_id]}
          type="select"
          label="Category"
          prompt="Not recorded"
          options={@categories}
        />
        <.input
          field={@form[:unit_id]}
          type="select"
          label="Unit that you count it in"
          prompt="Not recorded"
          options={@units}
        />
        <.input
          field={@form[:reorder_level]}
          type="number"
          label="Order more when the stock is below, if you give a number"
          min="0"
          step="any"
        />
        <.item_strength form={@form} />
        <.input field={@form[:note]} type="text" label="Note" maxlength="1000" />
        <footer><.button type="submit">Save the item</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The reorder levels of an item in a location, and the form that sets one."
  attr :form, :any, required: true
  attr :item, :map, required: true
  attr :wanted, :list, required: true
  attr :places, :list, required: true
  attr :place_names, :map, required: true
  attr :refused, :atom, required: true
  attr :problems, :list, required: true

  def reorder_form(assigns) do
    ~H"""
    <details id="reorder">
      <summary>Reorder levels in a location ({length(@wanted)})</summary>
      <.problems :if={@refused == :reorder} list={@problems} />
      <ul :if={@wanted != []} id="wanted">
        <li :for={level <- @wanted}>
          {upcase_first(place_words(level.location_id, @place_names))}: bring more when
          the stock there is below {InventoryWords.quantity(level.quantity, @item)}
        </li>
      </ul>
      <.form for={@form} id="reorder-form" phx-submit="set_level">
        <.input
          field={@form[:location_id]}
          type="select"
          label="Location"
          prompt="Choose a location"
          options={@places}
          required
        />
        <.input
          field={@form[:quantity]}
          type="number"
          label="Bring more when the stock there is below. No number removes the level"
          min="0"
          step="any"
        />
        <footer><.button type="submit">Save the level</.button></footer>
      </.form>
    </details>
    """
  end

  @doc "The removal of an item."
  attr :item, :map, required: true

  def remove_item(assigns) do
    ~H"""
    <details id="remove-item">
      <summary>Remove the item</summary>
      <p>
        The item leaves the inventory. Its lots and what happened to its stock stay in the
        history.
      </p>
      <.button phx-click="remove">Remove {@item.name}</.button>
    </details>
    """
  end

  def place_words(nil, _names), do: "no place in particular"
  def place_words("", _names), do: "no place in particular"
  def place_words(id, names), do: Map.get(names, id, "a location that is not here now")

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

  def in_stock(stock), do: Enum.filter(stock.lots, &(&1.places != []))
  defp empty(stock), do: Enum.filter(stock.lots, &(&1.places == []))

  def lot_choices(stock), do: Enum.map(stock.lots, &{lot_words(&1.lot), &1.lot.id})

  defp lot_words(%{expires_on: nil} = lot), do: InventoryWords.lot(lot)

  defp lot_words(lot),
    do: "#{InventoryWords.lot(lot)}, expires #{ResidentWords.date(lot.expires_on)}"

  # The stock of the page as the choices of a select: each lot in each place
  # where it has some. The value is the id of the lot, a bar, and the id of
  # the location or nothing.
  def sources(stock, place_names) do
    for %{lot: lot, places: places} <- stock.lots, {place, level} <- places do
      {"#{InventoryWords.lot(lot)}, #{place_words(place, place_names)}: " <>
         InventoryWords.quantity(level, stock.item), "#{lot.id}|#{place}"}
    end
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
    "#{upcase_first(place_words(short.location_id, names))} has " <>
      "#{InventoryWords.quantity(short.level, item)} that is good to use, and wants " <>
      "#{InventoryWords.quantity(short.wanted, item)} or more."
  end

  @doc """
  The items of the inventory, each with its level and its state: a
  collection with a search on the name, a filter on the category and on
  the state of the stock, a sort on the name, and pages (ADR 0088).

  `with_fault` is the function of the filter on the state: it takes the
  query and the filter, and gives the query of the items with that fault.
  """
  attr :organisation, :any, required: true
  attr :user, :any, required: true
  attr :url_state, :any, required: true, doc: "the state that the address holds (ADR 0084)"
  attr :categories, :list, required: true, doc: "each category, as the choices of a filter"
  attr :with_fault, :any, required: true

  def items_table(assigns) do
    ~H"""
    <section id="items" aria-labelledby="items-heading">
      <h2 id="items-heading">The items</h2>
      <Cinder.collection
        id="items"
        query={
          Inventory.query_to_items(%{},
            query: [
              load: [:stock, category: [:label], unit: [:label]],
              sort: [name: :asc, id: :asc]
            ],
            actor: @user,
            tenant: @organisation
          )
        }
        actor={@user}
        tenant={@organisation}
        url_state={@url_state}
        page_size={[default: 25, options: [25, 50, 100]]}
      >
        <:filter
          field="state"
          type="select"
          label="State"
          prompt="Any state"
          options={InventoryWords.fault_options()}
          fn={@with_fault}
        />
        <:empty :let={found}>
          <p :if={found.filtered?}>No item matches the search and the filters.</p>
          <p :if={not found.filtered?}>The inventory has no item yet.</p>
        </:empty>
        <:col :let={item} field="name" label="Item" sort search>
          <.link navigate={item_path(@organisation, item)}>{item.name}</.link>
        </:col>
        <:col
          :let={item}
          field="category_id"
          label="Category"
          filter={[type: :select, prompt: "Any category", options: @categories]}
        >
          <span data-label="Category">
            {(item.category && item.category.label) || "Not recorded"}
          </span>
        </:col>
        <:col :let={item} label="In stock">
          <span data-label="In stock">{InventoryWords.quantity(item.stock.level, item)}</span>
        </:col>
        <:col :let={item} label="State">
          <.state :for={{words, kind} <- InventoryWords.states(item.stock)} kind={kind}>
            {words}
          </.state>
        </:col>
      </Cinder.collection>
    </section>
    """
  end

  @doc "The form of a new item, for an administrator."
  attr :form, :any, required: true
  attr :categories, :any, required: true
  attr :units, :any, required: true

  def new_item(assigns) do
    ~H"""
    <details id="new-item">
      <summary>New item</summary>
      <.form for={@form} id="item" phx-submit="add">
        <.input field={@form[:name]} type="text" label="Name" maxlength="80" required />
        <.input
          field={@form[:category_id]}
          type="select"
          label="Category"
          prompt="Not recorded"
          options={@categories}
        />
        <.input
          field={@form[:unit_id]}
          type="select"
          label="Unit that you count it in"
          prompt="Not recorded"
          options={@units}
        />
        <.input
          field={@form[:reorder_level]}
          type="number"
          label="Order more when the stock is below, if you give a number"
          min="0"
          step="any"
        />
        <.item_strength form={@form} />
        <.input field={@form[:note]} type="text" label="Note" maxlength="1000" />
        <footer><.button type="submit">Add the item</.button></footer>
      </.form>
    </details>
    """
  end

  # The strength of a medication, in the form of an item: the same controls
  # as the dose calculator of the tools, which can fill it in (ADR 0072).
  attr :form, :any, required: true

  defp item_strength(assigns) do
    ~H"""
    <fieldset>
      <legend>Strength, for a medication</legend>
      <.strength_controls
        form={@form}
        hint="From the label: 1.5 mg in each mL. Leave it empty for each other item."
      />
    </fieldset>
    """
  end

  @doc """
  The fields of the strength of an item, for its form: the number, the unit
  of the mass, and what it is in each of. An item with no strength, or with
  one that the form cannot show, has none.
  """
  @spec strength_fields(map) :: map
  def strength_fields(item) do
    if Dosage.strength?(item.strength) do
      %{
        "strength" => Rescord.Units.Quantity.plain(item.strength),
        "strength_unit" => item.strength.unit.numerator.code,
        "strength_per" => item.strength.unit.denominator.code
      }
    else
      %{}
    end
  end

  @doc """
  Reads the strength that a form of an item sent, with the guards of the
  dose calculator: `{:ok, strength}`, `{:ok, nil}` for an empty field, or
  the words of what was refused.
  """
  @spec read_strength(map) :: {:ok, Rescord.Units.Quantity.t() | nil} | {:error, String.t()}
  def read_strength(fields) do
    case Dosage.strength(fields["strength"], fields["strength_unit"], fields["strength_per"]) do
      {:ok, strength} -> {:ok, strength}
      {:error, reason} -> {:error, "The strength: " <> ToolWords.problem({:strength, reason})}
    end
  end

  def item_path(organisation, item), do: ~p"/o/#{organisation.short_name}/inventory/#{item.id}"
  @doc "The form that changes a supplier."
  attr :supplier, :any, required: true

  def supplier_form(assigns) do
    ~H"""
    <details id={"change-details-#{@supplier.id}"}>
      <summary>Change</summary>
      <form id={"change-#{@supplier.id}"} phx-submit="revise">
        <input type="hidden" name="supplier_id" value={@supplier.id} />
        <.input
          id={"change-#{@supplier.id}-name"}
          name="change[name]"
          type="text"
          label={"Name of #{@supplier.name}"}
          value={@supplier.name}
          maxlength="120"
          required
        />
        <.input
          id={"change-#{@supplier.id}-contact"}
          name="change[contact]"
          type="text"
          label={"How to reach #{@supplier.name}"}
          value={@supplier.contact}
          maxlength="500"
        />
        <.input
          id={"change-#{@supplier.id}-note"}
          name="change[note]"
          type="text"
          label={"Note about #{@supplier.name}"}
          value={@supplier.note}
          maxlength="1000"
        />
        <.button type="submit">Save the supplier</.button>
      </form>
    </details>
    """
  end

  @doc "The removal of a supplier."
  attr :supplier, :any, required: true

  def remove_supplier(assigns) do
    ~H"""
    <details id={"remove-details-#{@supplier.id}"}>
      <summary>Remove</summary>
      <form id={"remove-#{@supplier.id}"} phx-submit="remove">
        <input type="hidden" name="supplier_id" value={@supplier.id} />
        <p>The lots that name this supplier keep their history.</p>
        <.button type="submit">Remove {@supplier.name}</.button>
      </form>
    </details>
    """
  end

  @doc "One supplier in the table, with the forms that keep it."
  attr :supplier, :any, required: true
  attr :can_change?, :any, required: true

  def supplier_row(assigns) do
    ~H"""
    <tr id={"supplier-#{@supplier.id}"}>
      <td>{@supplier.name}</td>
      <td data-label="How to reach it">{@supplier.contact || "Not recorded"}</td>
      <td data-label="Note">{@supplier.note}</td>
      <td :if={@can_change?}>
        <.supplier_form supplier={@supplier} />
        <.remove_supplier supplier={@supplier} />
      </td>
    </tr>
    """
  end

  @doc "The suppliers of the organisation."
  attr :can_change?, :any, required: true
  attr :suppliers, :any, required: true

  def suppliers_table(assigns) do
    ~H"""
    <div data-scroll>
      <table>
        <thead>
          <tr>
            <th scope="col">Supplier</th>
            <th scope="col">How to reach it</th>
            <th scope="col">Note</th>
            <th :if={@can_change?} scope="col">Actions</th>
          </tr>
        </thead>
        <tbody>
          <.supplier_row
            :for={supplier <- @suppliers}
            supplier={supplier}
            can_change?={@can_change?}
          />
        </tbody>
      </table>
    </div>
    """
  end

  @doc "The form of a new supplier, for an administrator."
  attr :form, :any, required: true

  def new_supplier(assigns) do
    ~H"""
    <details id="new-supplier">
      <summary>New supplier</summary>
      <.form for={@form} id="supplier" phx-submit="add">
        <.input field={@form[:name]} type="text" label="Name" maxlength="120" required />
        <.input
          field={@form[:contact]}
          type="text"
          label="How to reach it: a telephone number, an address, a person"
          maxlength="500"
        />
        <.input field={@form[:note]} type="text" label="Note" maxlength="1000" />
        <footer><.button type="submit">Add the supplier</.button></footer>
      </.form>
    </details>
    """
  end
end
