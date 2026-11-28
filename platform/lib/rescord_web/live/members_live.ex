defmodule RescordWeb.MembersLive do
  @moduledoc """
  The members of an organisation, at `/o/<short name>/members`.

  Each member of the organisation sees the list, with the role of each
  member. A person whose role has the power `:members` invites a person
  with a role, gives a member another role, and removes a member whose role
  does not have that power (ADR 0040). A root user does each of those for
  anybody.

  The forms offer only the roles that the person can give: those whose
  powers their own role has. The page shows a form or a button only when
  the role of the person has the grant for it. The policy and the
  validations of the member decide again when the action runs.
  """

  use RescordWeb, :live_view
  use Cinder.UrlSync

  import RescordWeb.AccountComponents

  alias Rescord.Accounts

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.role
    {:ok, roles} = Accounts.roles(options(socket))

    {:ok,
     socket
     |> assign(page_title: "Members", problems: [])
     |> assign(can_invite?: Accounts.role_can?(role, :invite_member))
     |> assign(roles: for(r <- roles, givable?(role, r), do: {to_string(r.name), r.id}))
     |> assign(all_roles: for(r <- roles, do: {to_string(r.name), r.id}))
     |> assign(member_role_id: Enum.find_value(roles, &(&1.key == :member && &1.id)))
     |> assign_invite_form()}
  end

  # A root user gives each role, and another person the roles whose powers
  # their own role has.
  defp givable?(:root, _role), do: true
  defp givable?(%{powers: own}, role), do: Enum.all?(role.powers, &(&1 in own))
  defp givable?(_none, _role), do: false

  defp assign_invite_form(socket) do
    assign(socket,
      invite_form:
        to_form(%{"email" => "", "role_id" => socket.assigns.member_role_id}, as: :invite)
    )
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # The id of a role of the form, when the page offered it, or `nil`, which
  # is the role of a member.
  defp offered(socket, id) do
    if Enum.any?(socket.assigns.roles, fn {_name, role_id} -> role_id == id end), do: id
  end

  @impl true
  def handle_event("invite", %{"invite" => %{"email" => address} = params}, socket)
      when is_binary(address) do
    case Accounts.invite_member(
           address,
           %{role_id: offered(socket, params["role_id"])},
           options(socket)
         ) do
      {:ok, _member} ->
        {:noreply,
         socket
         |> assign(problems: [])
         |> assign_invite_form()
         |> put_flash(:info, "An invitation is on its way to #{address}.")
         |> Cinder.Refresh.refresh_table("members")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event(
        "set_role",
        %{"member_id" => id, "member_role" => %{"role_id" => role_id}},
        socket
      )
      when is_binary(id) and is_binary(role_id) do
    case offered(socket, role_id) do
      nil -> {:noreply, socket}
      role_id -> change(socket, id, &Accounts.set_member_role(&1, role_id, &2))
    end
  end

  def handle_event("remove", %{"id" => id}, socket) when is_binary(id) do
    change(socket, id, &Accounts.remove_member/2)
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp change(socket, id, action) do
    with {:ok, %{} = member} <- Accounts.member(id, options(socket)),
         :ok <- done(action.(member, options(socket))) do
      # Each open page of that user has the role as it was.
      RescordWeb.UserAuth.disconnect(member.user_id)

      {:noreply, socket |> assign(problems: []) |> Cinder.Refresh.refresh_table("members")}
    else
      {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
      _not_found -> {:noreply, socket}
    end
  end

  # An update returns the record, and a removal returns `:ok`.
  defp done(:ok), do: :ok
  defp done({:ok, _record}), do: :ok
  defp done({:error, error}), do: {:error, error}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:members}
    >
      <.header icon={Icons.section(:members)}>
        Members
        <:subtitle>The people of {@organisation.name}</:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/roles"} data-variant="secondary">
            <.icon name="key" /> The roles
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <.members_table
        current_user={@current_user}
        organisation={@organisation}
        role={@role}
        roles={@roles}
        all_roles={@all_roles}
        url_state={@url_state}
      />

      <.invite_form :if={@can_invite?} invite_form={@invite_form} roles={@roles} />
    </Layouts.app>
    """
  end
end
