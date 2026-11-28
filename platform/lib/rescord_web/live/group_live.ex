defmodule RescordWeb.GroupLive do
  @moduledoc """
  One group, at `/o/<short name>/groups/<id>`.

  The page shows the members of the group and the words that say how they
  are related. A member adds a resident to the group, takes one out, changes
  the name, the kind and the words, and closes a group that is no more.

  A group that the person cannot read, and one that is not there, give the
  same answer: the list of the groups.
  """

  use RescordWeb, :live_view

  import RescordWeb.GroupComponents

  alias Rescord.{Lists, Locations, Residents}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = options(socket)

    with true <- is_binary(id),
         {:ok, %{} = group} <- Residents.group_with_facts(id, options) do
      {:ok, residents} = Residents.residents([load: [:name]] ++ options)
      {:ok, kinds} = Lists.offered_values(:group_kind, options)
      inside = MapSet.new(group.members, & &1.resident_id)

      {:ok,
       assign(socket,
         page_title: Residents.group_name(group),
         problems: [],
         group: group,
         home: home(group.id, options),
         others:
           residents
           |> Enum.reject(&MapSet.member?(inside, &1.id))
           |> Enum.map(&{&1.name || "No name yet", &1.id})
           |> Enum.sort(),
         kinds: kinds(kinds, group),
         join_form: to_form(%{"resident_id" => ""}, as: :member),
         form:
           to_form(
             %{
               "name" => group.name || "",
               "kind_id" => group.kind_id || "",
               "description" => group.description || ""
             },
             as: :group
           )
       )}
    else
      _no_group ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such group.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/groups")}
    end
  end

  defp home(group_id, options) do
    {:ok, placement} = Locations.group_home(group_id, options)
    placement
  end

  # The kinds that the form offers, and the kind of the group when it is retired.
  defp kinds(offered, group) do
    options = Enum.map(offered, &{to_string(&1.label), &1.id})

    if group.kind && not Enum.any?(offered, &(&1.id == group.kind_id)),
      do: [{to_string(group.kind.label), group.kind_id} | options],
      else: options
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp path(socket) do
    ~p"/o/#{socket.assigns.organisation.short_name}/groups/#{socket.assigns.group.id}"
  end

  @impl true
  def handle_event("join", %{"member" => %{"resident_id" => resident_id} = fields}, socket)
      when is_binary(resident_id) do
    at(socket, fields["at"], fn options ->
      Residents.join_group(
        %{resident_id: non_blank(resident_id), group_id: socket.assigns.group.id},
        options
      )
    end)
  end

  def handle_event("leave", %{"member_id" => id} = params, socket) when is_binary(id) do
    # Only a member of this group: the page has them in hand.
    case Enum.find(socket.assigns.group.members, &(&1.id == id)) do
      nil -> {:noreply, socket}
      member -> at(socket, get_in(params, ["leave", "at"]), &Residents.leave_group(member, &1))
    end
  end

  def handle_event("revise", %{"group" => fields}, socket) when is_map(fields) do
    attributes = %{
      name: non_blank(fields["name"]),
      kind_id: non_blank(fields["kind_id"]),
      description: non_blank(fields["description"])
    }

    socket.assigns.group
    |> Residents.revise_group(attributes, options(socket))
    |> after_write(socket)
  end

  def handle_event("close", _params, socket) do
    case Residents.close_group(socket.assigns.group, options(socket)) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "The group is closed.")
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/groups")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Runs a write at the time that the member gave, which is a local time of
  # the organisation and never after now, or at this instant with no time.
  defp at(socket, text, write) do
    case Rescord.Accounts.instant(socket.assigns.organisation, text) do
      {:ok, nil} ->
        socket |> options() |> write.() |> after_write(socket)

      {:ok, instant} ->
        ([as_of: instant] ++ options(socket)) |> write.() |> after_write(socket)

      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}
    end
  end

  # Opens the page again after a write, so that its forms are empty.
  defp after_write({:error, error}, socket),
    do: {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}

  defp after_write(_done, socket), do: {:noreply, push_navigate(socket, to: path(socket))}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:groups}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/groups"}>Groups</.link>
      </nav>

      <.header>
        {Residents.group_name(@group)}
        <:subtitle>{Residents.words(@group) || "No relation is recorded"}</:subtitle>
        <:actions :if={@group.members != []}>
          <.link
            navigate={~p"/o/#{@organisation.short_name}/groups/#{@group.id}/measurements"}
            data-variant="secondary"
          >
            Measurements
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <.about_group
        group={@group}
        home={@home}
        organisation={@organisation}
        role={@role}
        form={@form}
        kinds={@kinds}
      />

      <.group_members
        group={@group}
        organisation={@organisation}
        role={@role}
        others={@others}
        join_form={@join_form}
      />

      <.close_group_section :if={can?(@role, :group, :close)} />
    </Layouts.app>
    """
  end
end
