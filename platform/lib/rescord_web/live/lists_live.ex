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

  import RescordWeb.ListComponents

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

        %{
          key: key,
          name: name,
          values:
            Enum.map(
              values,
              &%{id: &1.id, label: to_string(&1.name), origin: nil, retired?: false}
            ),
          unused: []
        }
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
            Enum.map(
              values,
              &%{
                id: &1.id,
                label: to_string(&1.label),
                origin: if(&1.base_id, do: "shared", else: "local"),
                retired?: &1.retired,
                unit_ids: Map.get(&1, :unit_ids, []),
                standard_unit_id: Map.get(&1, :standard_unit_id),
                lowest: Map.get(&1, :lowest),
                highest: Map.get(&1, :highest),
                soon_days: Map.get(&1, :soon_days)
              }
            ),
          unused: Enum.map(unused, &{to_string(&1.name), &1.id})
        }
      end

    # The measure kinds name their units from the list of units. A kind
    # can name a retired unit, so the page has each unit too.
    all_units = lists |> Enum.find(&(&1.key == :unit)) |> Map.fetch!(:values)
    units = all_units |> Enum.reject(& &1.retired?) |> Enum.map(&{&1.label, &1.id})

    assign(socket,
      lists: Enum.map(lists, &Map.merge(&1, %{units: units, all_units: all_units}))
    )
  end

  @impl true
  def handle_event("add", %{"dimension" => dimension, "value" => %{"name" => name}}, socket)
      when is_binary(name) do
    write(socket, dimension, &"#{&1} is added.", fn key ->
      if socket.assigns.shared?,
        do: Lists.add_shared_value(key, name, options(socket)),
        else: Lists.add_local_value(key, name, options(socket))
    end)
  end

  def handle_event("retire", %{"dimension" => dimension, "id" => id}, socket)
      when is_binary(id) do
    if socket.assigns.shared?,
      do: {:noreply, socket},
      else:
        write(
          socket,
          dimension,
          &"#{&1} is retired.",
          &Lists.retire_value(&1, id, options(socket))
        )
  end

  def handle_event("restore", %{"dimension" => dimension, "id" => id}, socket)
      when is_binary(id) do
    if socket.assigns.shared?,
      do: {:noreply, socket},
      else:
        write(
          socket,
          dimension,
          &"#{&1} is restored.",
          &Lists.restore_value(&1, id, options(socket))
        )
  end

  def handle_event("use", %{"dimension" => dimension, "value" => %{"base_id" => id}}, socket)
      when is_binary(id) do
    if socket.assigns.shared? do
      {:noreply, socket}
    else
      write(
        socket,
        dimension,
        &"#{&1} is added.",
        &Lists.use_shared_value(&1, id, options(socket))
      )
    end
  end

  def handle_event("set_units", %{"value_id" => id} = params, socket) when is_binary(id) do
    ids =
      case params do
        %{"units" => %{"ids" => ids}} when is_list(ids) -> Enum.filter(ids, &is_binary/1)
        _no_unit -> []
      end

    value_write(socket, :measure_kind, id, &Lists.set_units(&1, ids, options(socket)))
  end

  def handle_event("set_standard_unit", %{"value_id" => id} = params, socket)
      when is_binary(id) do
    unit_id =
      case params do
        %{"standard" => %{"unit_id" => unit_id}} -> non_blank(unit_id)
        _no_unit -> nil
      end

    value_write(socket, :measure_kind, id, &Lists.set_standard_unit(&1, unit_id, options(socket)))
  end

  def handle_event("set_range", %{"value_id" => id} = params, socket) when is_binary(id) do
    range = Map.get(params, "range", %{})
    lowest = non_blank(range["lowest"])
    highest = non_blank(range["highest"])

    value_write(socket, :measure_kind, id, &Lists.set_range(&1, lowest, highest, options(socket)))
  end

  def handle_event("set_soon_days", %{"value_id" => id} = params, socket) when is_binary(id) do
    days =
      case params do
        %{"soon" => %{"days" => days}} -> non_blank(days)
        _no_days -> nil
      end

    value_write(socket, :item_category, id, &Lists.set_soon_days(&1, days, options(socket)))
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Changes a value of a list of this page: the page has them in hand.
  defp value_write(%{assigns: %{shared?: true}} = socket, _key, _id, _action),
    do: {:noreply, socket}

  defp value_write(socket, key, id, action) do
    list = Enum.find(socket.assigns.lists, &(&1.key == key))

    if Enum.any?(list.values, &(&1.id == id)) do
      write(socket, Atom.to_string(key), &"#{&1} is saved.", fn _key -> action.(id) end)
    else
      {:noreply, socket}
    end
  end

  # `words` says what the write did, from the name of the value that it
  # wrote (issue 35).
  defp write(socket, dimension, words, action) do
    with {:ok, key} <- Lists.dimension(dimension),
         {:ok, value} <- action.(key) do
      # A new page has the value in its list, and its forms are empty: a
      # form that stays on the page keeps what the person typed.
      {:noreply,
       socket
       |> put_flash(:info, words.(Lists.label_of(value, options(socket))))
       |> push_navigate(to: path(socket))}
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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={assigns[:organisation]}
      inbox={assigns[:inbox]}
      ruby={assigns[:ruby?] || false}
      section={if assigns[:organisation], do: :lists, else: :root}
    >
      <.header icon={Icons.section(:lists)}>
        <:crumb :if={@shared?} navigate={~p"/root"}>Root</:crumb>
        {@page_title}
        <:subtitle :if={@shared?}>
          The values that each organisation can use. An organisation adds the ones that it needs to
          its own lists.
        </:subtitle>
        <:subtitle :if={!@shared?}>
          The choices in the forms of {@organisation.name}: species, kinds of task, units, categories
          of items and expenses, and more. Add a shared value of Rescord, or a local value of your
          own. Retire a value to stop offering it: the records that have it keep it.
        </:subtitle>
      </.header>

      <.problems list={@problems} />

      <.value_list
        :for={list <- @lists}
        list={list}
        can_change?={@can_change?}
        shared?={@shared?}
      />
    </Layouts.app>
    """
  end
end
