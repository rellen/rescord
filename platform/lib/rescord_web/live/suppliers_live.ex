defmodule RescordWeb.SuppliersLive do
  @moduledoc """
  The suppliers of an organisation, at `/o/<short name>/inventory/suppliers`
  (ADR 0034). Each member reads the list. An administrator adds a supplier,
  changes one and removes one.
  """

  use RescordWeb, :live_view

  import RescordWeb.InventoryComponents

  alias Rescord.{Accounts, Inventory}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, suppliers} = Inventory.suppliers(options(socket))

    {:ok,
     assign(socket,
       page_title: "Suppliers",
       problems: [],
       suppliers: Enum.sort_by(suppliers, &String.downcase(&1.name)),
       can_change?: Inventory.role_can?(socket.assigns.role, :supplier, :add),
       form: to_form(%{}, as: :supplier)
     )}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/inventory/suppliers"

  defp facts(fields) do
    %{
      name: non_blank(fields["name"]),
      contact: non_blank(fields["contact"]),
      note: non_blank(fields["note"])
    }
  end

  @impl true
  def handle_event("add", %{"supplier" => fields}, socket) when is_map(fields) do
    case Inventory.add_supplier(facts(fields), options(socket)) do
      {:ok, _supplier} ->
        {:noreply, push_navigate(socket, to: path(socket))}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           form: typed_form(fields, as: :supplier)
         )}
    end
  end

  def handle_event("revise", %{"supplier_id" => id, "change" => fields}, socket)
      when is_map(fields),
      do: act(socket, id, &Inventory.revise_supplier(&1, facts(fields), options(socket)))

  def handle_event("remove", %{"supplier_id" => id}, socket),
    do: act(socket, id, &Inventory.remove_supplier(&1, options(socket)))

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Runs an action on a supplier of this page: the page has them in hand.
  defp act(socket, id, action) do
    case Enum.find(socket.assigns.suppliers, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      supplier ->
        case action.(supplier) do
          {:error, error} ->
            {:noreply, assign(socket, problems: Accounts.error_messages(error))}

          _done ->
            {:noreply, push_navigate(socket, to: path(socket))}
        end
    end
  end

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
      <.header icon={Icons.section(:suppliers)}>
        Suppliers
        <:subtitle>Where {@organisation.name} gets its supplies</:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/inventory"} data-variant="secondary">
            <.icon name="archive-box" /> The inventory
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p :if={@suppliers == []}>There is no supplier yet.</p>
      <.suppliers_table
        :if={@suppliers != []}
        can_change?={@can_change?}
        suppliers={@suppliers}
      />

      <.new_supplier :if={@can_change?} form={@form} />
    </Layouts.app>
    """
  end
end
