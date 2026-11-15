defmodule RescordWeb.ListsLive do
  @moduledoc """
  The lists of values, on two pages:

    * `/o/<short name>/lists`: the lists of an organisation. Each member
      reads them. An administrator adds a shared value to a list, and adds a
      local value with a name of its own.
    * `/root/lists`: the base lists, which all organisations share. Only a
      root user opens the page, and adds a shared value there.

  The key of a dimension comes from the browser as text. The page finds the
  dimension with `Rescord.Lists.dimension/1`, which makes no atom.
  """

  use RescordWeb, :live_view

  alias Rescord.Lists

  @impl true
  def mount(_params, _session, socket) do
    shared? = socket.assigns.live_action == :shared

    {:ok,
     socket
     |> assign(shared?: shared?, problems: [])
     |> assign(page_title: if(shared?, do: "Shared lists", else: "Lists"))
     |> assign(can_change?: shared? or Lists.role_can_change?(socket.assigns[:role]))
     |> assign_lists()}
  end

  defp options(%{assigns: %{shared?: true} = assigns}), do: [actor: assigns.current_user]

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_lists(%{assigns: %{shared?: true}} = socket) do
    lists =
      for {key, name} <- Lists.dimensions() do
        {:ok, values} = Lists.shared_values(key, options(socket))
        %{key: key, name: name, values: Enum.map(values, &{to_string(&1.name), nil}), unused: []}
      end

    assign(socket, lists: lists)
  end

  defp assign_lists(socket) do
    lists =
      for {key, name} <- Lists.dimensions() do
        {:ok, values} = Lists.values(key, options(socket))
        {:ok, unused} = Lists.unused_shared_values(key, options(socket))

        %{
          key: key,
          name: name,
          values:
            Enum.map(values, &{to_string(&1.label), if(&1.base_id, do: "shared", else: "local")}),
          unused: Enum.map(unused, &{to_string(&1.name), &1.id})
        }
      end

    assign(socket, lists: lists)
  end

  @impl true
  def handle_event("add", %{"dimension" => dimension, "value" => %{"name" => name}}, socket)
      when is_binary(name) do
    write(socket, dimension, fn key ->
      if socket.assigns.shared?,
        do: Lists.add_shared_value(key, name, options(socket)),
        else: Lists.add_local_value(key, name, options(socket))
    end)
  end

  def handle_event("use", %{"dimension" => dimension, "value" => %{"base_id" => id}}, socket)
      when is_binary(id) do
    if socket.assigns.shared? do
      {:noreply, socket}
    else
      write(socket, dimension, &Lists.use_shared_value(&1, id, options(socket)))
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp write(socket, dimension, action) do
    with {:ok, key} <- Lists.dimension(dimension),
         {:ok, _value} <- action.(key) do
      # A new page has the value in its list, and its forms are empty: a
      # form that stays on the page keeps what the person typed.
      {:noreply, push_navigate(socket, to: path(socket))}
    else
      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}

      :error ->
        {:noreply, socket}
    end
  end

  defp path(%{assigns: %{shared?: true}}), do: ~p"/root/lists"
  defp path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/lists"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={assigns[:organisation]}>
      <.header>
        {@page_title}
        <:subtitle :if={@shared?}>
          The values that each organisation can use. An organisation adds the ones that it needs to
          its own lists.
        </:subtitle>
        <:subtitle :if={!@shared?}>
          The values that {@organisation.name} uses to describe a resident.
        </:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section :for={list <- @lists} aria-labelledby={"list-#{list.key}"}>
        <h2 id={"list-#{list.key}"}>{list.name}</h2>

        <p :if={list.values == []}>The list is empty.</p>
        <ul :if={list.values != []}>
          <li :for={{label, origin} <- list.values}>
            {label}
            <small :if={origin}>({origin})</small>
          </li>
        </ul>

        <details :if={@can_change?}>
          <summary>Add a value to {String.downcase(list.name)}</summary>
          <form :if={list.unused != []} id={"use-#{list.key}"} phx-submit="use">
            <input type="hidden" name="dimension" value={list.key} />
            <.input
              id={"use-#{list.key}-value"}
              name="value[base_id]"
              type="select"
              label={"A shared value for #{String.downcase(list.name)}"}
              options={list.unused}
              value=""
            />
            <.button
              type="submit"
              aria-label={"Add the shared value to #{String.downcase(list.name)}"}
            >
              Add the shared value
            </.button>
          </form>

          <form id={"add-#{list.key}"} phx-submit="add">
            <input type="hidden" name="dimension" value={list.key} />
            <.input
              id={"add-#{list.key}-name"}
              name="value[name]"
              type="text"
              label={
                if @shared?,
                  do: "A new shared value for #{String.downcase(list.name)}",
                  else: "A new local value for #{String.downcase(list.name)}"
              }
              value=""
              maxlength="60"
              required
            />
            <.button type="submit" aria-label={"Add the value to #{String.downcase(list.name)}"}>
              Add the value
            </.button>
          </form>
        </details>
      </section>
    </Layouts.app>
    """
  end
end
