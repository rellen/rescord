defmodule RescordWeb.SuppliersLive do
  @moduledoc """
  The suppliers of an organisation, at `/o/<short name>/inventory/suppliers`
  (ADR 0034). Each member reads the list. An administrator adds a supplier,
  changes one and removes one.
  """

  use RescordWeb, :live_view

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
    %{name: text(fields["name"]), contact: text(fields["contact"]), note: text(fields["note"])}
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
           form: to_form(fields, as: :supplier)
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

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Suppliers
        <:subtitle>Where {@organisation.name} gets its supplies</:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/inventory"} data-variant="secondary">
            The inventory
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p :if={@suppliers == []}>There is no supplier yet.</p>
      <div :if={@suppliers != []} data-scroll>
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
            <tr :for={supplier <- @suppliers} id={"supplier-#{supplier.id}"}>
              <td>{supplier.name}</td>
              <td>{supplier.contact || "Not recorded"}</td>
              <td>{supplier.note}</td>
              <td :if={@can_change?}>
                <details id={"change-details-#{supplier.id}"}>
                  <summary>Change</summary>
                  <form id={"change-#{supplier.id}"} phx-submit="revise">
                    <input type="hidden" name="supplier_id" value={supplier.id} />
                    <.input
                      id={"change-#{supplier.id}-name"}
                      name="change[name]"
                      type="text"
                      label={"Name of #{supplier.name}"}
                      value={supplier.name}
                      maxlength="120"
                      required
                    />
                    <.input
                      id={"change-#{supplier.id}-contact"}
                      name="change[contact]"
                      type="text"
                      label={"How to reach #{supplier.name}"}
                      value={supplier.contact}
                      maxlength="500"
                    />
                    <.input
                      id={"change-#{supplier.id}-note"}
                      name="change[note]"
                      type="text"
                      label={"Note about #{supplier.name}"}
                      value={supplier.note}
                      maxlength="1000"
                    />
                    <.button type="submit">Save the supplier</.button>
                  </form>
                </details>
                <details id={"remove-details-#{supplier.id}"}>
                  <summary>Remove</summary>
                  <form id={"remove-#{supplier.id}"} phx-submit="remove">
                    <input type="hidden" name="supplier_id" value={supplier.id} />
                    <p>The lots that name this supplier keep their history.</p>
                    <.button type="submit">Remove {supplier.name}</.button>
                  </form>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <details :if={@can_change?} id="new-supplier">
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
    </Layouts.app>
    """
  end
end
