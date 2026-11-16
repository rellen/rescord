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
  def handle_event("join", %{"member" => %{"resident_id" => resident_id}}, socket)
      when is_binary(resident_id) do
    %{resident_id: text(resident_id), group_id: socket.assigns.group.id}
    |> Residents.join_group(options(socket))
    |> after_write(socket)
  end

  def handle_event("leave", %{"id" => id}, socket) when is_binary(id) do
    # Only a member of this group: the page has them in hand.
    case Enum.find(socket.assigns.group.members, &(&1.id == id)) do
      nil -> {:noreply, socket}
      member -> member |> Residents.leave_group(options(socket)) |> after_write(socket)
    end
  end

  def handle_event("revise", %{"group" => fields}, socket) when is_map(fields) do
    attributes = %{
      name: text(fields["name"]),
      kind_id: text(fields["kind_id"]),
      description: text(fields["description"])
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

  # Opens the page again after a write, so that its forms are empty.
  defp after_write({:error, error}, socket),
    do: {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}

  defp after_write(_done, socket), do: {:noreply, push_navigate(socket, to: path(socket))}

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  defp can?(role, subject, action), do: Residents.role_can?(role, subject, action)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/groups"}>Groups</.link>
      </nav>

      <.header>
        {Residents.group_name(@group)}
        <:subtitle>{Residents.words(@group) || "No relation is recorded"}</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section aria-labelledby="about-heading">
        <h2 id="about-heading">About</h2>
        <.list>
          <:item title="Kind">{if @group.kind, do: @group.kind.label, else: "Not recorded"}</:item>
          <:item title="Lives in">
            <.link
              :if={@home}
              navigate={~p"/o/#{@organisation.short_name}/housing/#{@home.location_id}"}
            >{@home.location.name}</.link>
            <span :if={is_nil(@home)}>No place in the housing yet</span>
          </:item>
          <:item title="How they are related">
            {Residents.words(@group) || "No relation is recorded"}
            <small :if={@group.description}>(the words of a member)</small>
          </:item>
        </.list>

        <details :if={can?(@role, :group, :revise)}>
          <summary>Change the group</summary>
          <.form for={@form} id="group" phx-submit="revise">
            <.input
              field={@form[:name]}
              type="text"
              label="Name, if the group has one"
              maxlength="80"
            />
            <.input
              field={@form[:kind_id]}
              type="select"
              label="Kind"
              prompt="Not recorded"
              options={@kinds}
            />
            <.input
              field={@form[:description]}
              type="text"
              label="How they are related, in your words. Leave it empty for the words of Rescord"
              maxlength="200"
            />
            <footer><.button type="submit">Save the group</.button></footer>
          </.form>
        </details>
      </section>

      <section aria-labelledby="members-heading">
        <h2 id="members-heading">Members</h2>
        <p :if={@group.members == []}>The group has no member.</p>
        <ul :if={@group.members != []}>
          <li :for={member <- @group.members}>
            <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{member.resident_id}"}>
              {member.resident.name || "No name yet"}
            </.link>
            <.button
              :if={can?(@role, :group_member, :leave)}
              phx-click="leave"
              phx-value-id={member.id}
              aria-label={"Take #{member.resident.name || "the resident with no name"} out of the group"}
            >
              Take out
            </.button>
          </li>
        </ul>

        <details :if={can?(@role, :group_member, :join) and @others != []}>
          <summary>Add a member</summary>
          <.form for={@join_form} id="member" phx-submit="join">
            <.input
              field={@join_form[:resident_id]}
              type="select"
              label="Resident"
              prompt="Choose"
              options={@others}
              required
            />
            <footer><.button type="submit">Add to the group</.button></footer>
          </.form>
        </details>
      </section>

      <section :if={can?(@role, :group, :close)} aria-labelledby="close-heading">
        <h2 id="close-heading">Close</h2>
        <details>
          <summary>Close this group</summary>
          <p>Close a group that is no more. Its history stays.</p>
          <.button phx-click="close">Close the group</.button>
        </details>
      </section>
    </Layouts.app>
    """
  end
end
