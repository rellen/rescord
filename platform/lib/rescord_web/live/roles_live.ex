defmodule RescordWeb.RolesLive do
  @moduledoc """
  The roles of an organisation, at `/o/<short name>/roles` (ADR 0040).

  Each member reads the roles and what each one may do. A person whose role
  has the power `:roles` defines a role, ticks its powers, changes a role,
  and removes a role that no member has. A person gives only the powers
  that their own role has: the action refuses another one.

  After a change to a role, each open page of each member with that role
  closes, so it opens again with the new powers (ADR 0036).

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it: `RescordWeb.RoleWords.power_of/1` finds each
  power in the list that Rescord knows.
  """

  use RescordWeb, :live_view

  import RescordWeb.RoleComponents

  alias Rescord.Accounts
  alias Rescord.Accounts.Role
  alias RescordWeb.RoleWords

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.role

    {:ok,
     socket
     |> assign(
       page_title: "Roles",
       problems: [],
       refused: nil,
       can_define?: Accounts.granted?(role, Role, :define),
       can_revise?: Accounts.granted?(role, Role, :revise),
       can_remove?: Accounts.granted?(role, Role, :remove)
     )
     |> assign_roles()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_roles(socket) do
    options = options(socket)
    {:ok, roles} = Accounts.roles(options)
    {:ok, members} = Accounts.members(options)

    assign(socket,
      roles: roles,
      counts: Enum.frequencies_by(members, & &1.role_id),
      members: members
    )
  end

  defp path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/roles"

  # The facts of a role from the fields of a form.
  defp facts(fields) do
    powers =
      for text <- List.wrap(fields["powers"]),
          {:ok, power} <- [RoleWords.power_of(text)],
          uniq: true,
          do: power

    %{name: non_blank(fields["name"]), powers: powers}
  end

  @impl true
  def handle_event("define", %{"role" => fields}, socket) when is_map(fields) do
    case Accounts.define_role(facts(fields), options(socket)) do
      {:ok, _role} -> {:noreply, push_navigate(socket, to: path(socket))}
      {:error, error} -> {:noreply, refuse(socket, {:define, typed_fields(fields)}, error)}
    end
  end

  def handle_event("revise", %{"role_id" => id, "role" => fields}, socket)
      when is_binary(id) and is_map(fields) do
    case Enum.find(socket.assigns.roles, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      role ->
        case Accounts.revise_role(role, facts(fields), options(socket)) do
          {:ok, _role} ->
            # Each open page of a member with this role has the old powers.
            for member <- socket.assigns.members, member.role_id == id do
              RescordWeb.UserAuth.disconnect(member.user_id)
            end

            {:noreply, push_navigate(socket, to: path(socket))}

          {:error, error} ->
            {:noreply, refuse(socket, {:revise, id, typed_fields(fields)}, error)}
        end
    end
  end

  def handle_event("remove", %{"id" => id}, socket) when is_binary(id) do
    with %{} = role <- Enum.find(socket.assigns.roles, &(&1.id == id)),
         :ok <- Accounts.remove_role(role, options(socket)) do
      {:noreply, push_navigate(socket, to: path(socket))}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, refuse(socket, nil, error)}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The problems are in the form that the person sent, when the page drew
  # it for them, and else below the header.
  defp refuse(socket, refused, error) do
    refused =
      case refused do
        {:define, _fields} -> if socket.assigns.can_define?, do: refused
        {:revise, _id, _fields} -> if socket.assigns.can_revise?, do: refused
        nil -> nil
      end

    assign(socket, problems: Accounts.error_messages(error), refused: refused)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:members}
    >
      <.header>
        Roles
        <:subtitle>What each person of {@organisation.name} may do</:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/members"} data-variant="secondary">
            The members
          </.link>
        </:actions>
      </.header>

      <p>
        Each role reads the residents, the journal, the tasks, the housing and the inventory. The
        powers of a role say what else it may do. You give a role only the powers that your own
        role has.
      </p>

      <.problems :if={is_nil(@refused)} list={@problems} />

      <.roles_list
        roles={@roles}
        counts={@counts}
        can_revise?={@can_revise?}
        can_remove?={@can_remove?}
        refused={@refused}
        problems={@problems}
      />

      <.new_role :if={@can_define?} refused={@refused} problems={@problems} />
    </Layouts.app>
    """
  end
end
