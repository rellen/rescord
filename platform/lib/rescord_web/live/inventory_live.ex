defmodule RescordWeb.InventoryLive do
  @moduledoc """
  The inventory of an organisation, at `/o/<short name>/inventory`: each
  item with its level and what a member must know about it (ADR 0034).

  Each member reads the inventory. An administrator adds an item here. The
  page of an item has its lots and what happened to its stock.
  """

  use RescordWeb, :live_view

  alias Rescord.{Accounts, Inventory, Lists}
  alias RescordWeb.InventoryWords

  @impl true
  def mount(_params, _session, socket) do
    options = options(socket)
    {:ok, stock} = Inventory.stock(options)
    can_add? = Inventory.role_can?(socket.assigns.role, :item, :add)

    {categories, units} =
      if can_add? do
        {:ok, categories} = Lists.offered_values(:item_category, options)
        {:ok, units} = Lists.offered_values(:unit, options)
        {choices(categories), choices(units)}
      else
        {[], []}
      end

    {:ok,
     assign(socket,
       page_title: "Inventory",
       problems: [],
       stock: stock,
       can_add?: can_add?,
       categories: categories,
       units: units,
       form: to_form(%{}, as: :item)
     )}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp choices(values), do: Enum.map(values, &{to_string(&1.label), &1.id})

  @impl true
  def handle_event("add", %{"item" => fields}, socket) when is_map(fields) do
    attributes = %{
      name: text(fields["name"]),
      category_id: text(fields["category_id"]),
      unit_id: text(fields["unit_id"]),
      reorder_level: text(fields["reorder_level"]),
      note: text(fields["note"])
    }

    case Inventory.add_item(attributes, options(socket)) do
      {:ok, item} ->
        {:noreply, push_navigate(socket, to: item_path(socket.assigns.organisation, item))}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           form: to_form(fields, as: :item)
         )}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  defp item_path(organisation, item), do: ~p"/o/#{organisation.short_name}/inventory/#{item.id}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Inventory
        <:subtitle>The supplies of {@organisation.name}</:subtitle>
        <:actions>
          <.link
            navigate={~p"/o/#{@organisation.short_name}/inventory/suppliers"}
            data-variant="secondary"
          >
            Suppliers
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section aria-labelledby="items-heading">
        <h2 id="items-heading">The items</h2>
        <p :if={@stock == []}>The inventory has no item yet.</p>
        <div :if={@stock != []} data-scroll>
          <table>
            <thead>
              <tr>
                <th scope="col">Item</th>
                <th scope="col">Category</th>
                <th scope="col">In stock</th>
                <th scope="col">State</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={stock <- @stock} id={"item-#{stock.item.id}"}>
                <td>
                  <.link navigate={item_path(@organisation, stock.item)}>{stock.item.name}</.link>
                </td>
                <td>{(stock.item.category && stock.item.category.label) || "Not recorded"}</td>
                <td>{InventoryWords.quantity(stock.level, stock.item)}</td>
                <td>
                  <.state :for={{words, kind} <- InventoryWords.states(stock)} kind={kind}>
                    {words}
                  </.state>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <details :if={@can_add?} id="new-item">
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
          <.input field={@form[:note]} type="text" label="Note" maxlength="1000" />
          <footer><.button type="submit">Add the item</.button></footer>
        </.form>
      </details>
    </Layouts.app>
    """
  end
end
