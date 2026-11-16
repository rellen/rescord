defmodule RescordWeb.InventoryLive do
  @moduledoc """
  The inventory of an organisation, at `/o/<short name>/inventory`: each
  item with its level and what a member must know about it (ADR 0034).

  Each member reads the inventory. An administrator adds an item here. The
  page of an item has its lots and what happened to its stock.
  """

  use RescordWeb, :live_view

  import RescordWeb.InventoryComponents

  alias Rescord.{Accounts, Inventory, Lists}

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
      name: non_blank(fields["name"]),
      category_id: non_blank(fields["category_id"]),
      unit_id: non_blank(fields["unit_id"]),
      reorder_level: non_blank(fields["reorder_level"]),
      note: non_blank(fields["note"])
    }

    case Inventory.add_item(attributes, options(socket)) do
      {:ok, item} ->
        {:noreply, push_navigate(socket, to: item_path(socket.assigns.organisation, item))}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           form: typed_form(fields, as: :item)
         )}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

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

      <.items_table stock={@stock} organisation={@organisation} />

      <.new_item :if={@can_add?} form={@form} categories={@categories} units={@units} />
    </Layouts.app>
    """
  end
end
