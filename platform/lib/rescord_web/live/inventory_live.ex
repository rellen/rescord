defmodule RescordWeb.InventoryLive do
  @moduledoc """
  The inventory of an organisation, at `/o/<short name>/inventory`: each
  item with its level and what a member must know about it (ADR 0034).

  Each member reads the inventory. An administrator adds an item here. The
  page of an item has its lots and what happened to its stock.

  The items are a collection (ADR 0088): a search on the name, a filter on
  the category and on the state of the stock, and pages. The address holds
  them (ADR 0084), so `?state=short` is the list of the items to order.
  Cinder reads those parameters, and this page reads none of them.

  The page shows what another person changed in the inventory, without a
  reload (ADR 0096).
  """

  use RescordWeb, :live_view
  use Cinder.UrlSync

  import RescordWeb.InventoryComponents

  alias Rescord.{Accounts, Inventory, Lists}
  alias RescordWeb.InventoryWords

  @impl true
  def mount(_params, _session, socket) do
    options = options(socket)
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
     socket
     |> LiveChanges.listen([Inventory], &read_again/1)
     |> assign(
       page_title: "Inventory",
       as_of: DateTime.utc_now(),
       problems: [],
       all_categories: all_categories(options),
       with_fault: &with_fault(&1, &2, options),
       can_add?: can_add?,
       categories: categories,
       units: units,
       form: to_form(%{}, as: :item)
     )}
  end

  # The collection reads as of the instant of `:as_of` (ADR 0096, "With
  # Cinder"): a query of a temporal resource holds the instant at which it
  # was built, so a refresh of the same query would read the past. A new
  # instant is a new query, and Cinder reads it again.
  defp read_again(socket), do: assign(socket, as_of: DateTime.utc_now())

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp choices(values), do: Enum.map(values, &{to_string(&1.label), &1.id})

  # Each category of the organisation, as the choices of the filter. A
  # category that an administrator retired is one of them: an item can
  # still have it.
  defp all_categories(options) do
    case Lists.values(:item_category, options) do
      {:ok, values} -> choices(values)
      {:error, _error} -> []
    end
  end

  # The filter on the state of the stock. The value comes from the address
  # or from the form of the filter: a value that names no fault changes
  # nothing. The stock is that of the instant of the query.
  defp with_fault(query, %{value: value}, options) do
    case InventoryWords.fault_of(value) do
      nil -> query
      fault -> Inventory.with_fault(query, fault, [as_of: query.as_of] ++ options)
    end
  end

  defp with_fault(query, _filter, _options), do: query

  @impl true
  def handle_event("add", %{"item" => fields}, socket) when is_map(fields) do
    attributes = %{
      name: non_blank(fields["name"]),
      category_id: non_blank(fields["category_id"]),
      unit_id: non_blank(fields["unit_id"]),
      reorder_level: non_blank(fields["reorder_level"]),
      note: non_blank(fields["note"])
    }

    with {:ok, strength} <- read_strength(fields),
         {:ok, item} <-
           Inventory.add_item(Map.put(attributes, :strength, strength), options(socket)) do
      {:noreply,
       socket
       |> put_flash(:info, "#{item.name} is added to the inventory.")
       |> push_navigate(to: item_path(socket.assigns.organisation, item))}
    else
      {:error, words} when is_binary(words) ->
        {:noreply, assign(socket, problems: [words], form: typed_form(fields, as: :item))}

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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:inventory}
    >
      <.header icon={Icons.section(:inventory)}>
        Inventory
        <:subtitle>The supplies of {@organisation.name}</:subtitle>
        <:actions>
          <.link
            navigate={~p"/o/#{@organisation.short_name}/inventory/suppliers"}
            data-variant="secondary"
          >
            <.icon name={Icons.section(:suppliers)} /> Suppliers
          </.link>
          <RescordWeb.ReportComponents.report_link
            id="stock-report"
            href={~p"/o/#{@organisation.short_name}/reports/stock.pdf"}
          >
            Stock report (PDF)
          </RescordWeb.ReportComponents.report_link>
        </:actions>
      </.header>

      <.problems list={@problems} />

      <.new_item :if={@can_add?} form={@form} categories={@categories} units={@units} />

      <.items_table
        organisation={@organisation}
        user={@current_user}
        url_state={@url_state}
        as_of={@as_of}
        categories={@all_categories}
        with_fault={@with_fault}
      />
    </Layouts.app>
    """
  end
end
