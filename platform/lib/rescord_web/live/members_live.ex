defmodule RescordWeb.MembersLive do
  @moduledoc """
  The members of an organisation, at `/o/<short name>/members`.

  Each member of the organisation sees the list. An administrator invites a
  member, makes a member an administrator, and removes a member. A root user
  does each of those, and also invites an administrator.

  The page shows a form or a button only when the role of the person has the
  grant for it. The policy of the member decides again when the action runs.
  """

  use RescordWeb, :live_view

  alias Rescord.Accounts

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.role

    {:ok,
     socket
     |> assign(page_title: "Members", problems: [])
     |> assign(can_invite?: Accounts.role_can?(role, :invite_member))
     |> assign(can_invite_administrator?: Accounts.role_can?(role, :invite_administrator))
     |> assign_invite_form()}
  end

  defp assign_invite_form(socket) do
    assign(socket, invite_form: to_form(%{"email" => "", "role" => "member"}, as: :invite))
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  @impl true
  def handle_event("invite", %{"invite" => %{"email" => address} = params}, socket)
      when is_binary(address) do
    # A role that the form did not offer is refused by the policy.
    invite =
      case params["role"] do
        "administrator" -> &Accounts.invite_administrator/2
        _member -> &Accounts.invite_member/2
      end

    case invite.(address, options(socket)) do
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

  def handle_event("make_administrator", %{"id" => id}, socket) when is_binary(id) do
    change(socket, id, &Accounts.make_administrator/2)
  end

  def handle_event("remove", %{"id" => id}, socket) when is_binary(id) do
    change(socket, id, &Accounts.remove_member/2)
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp change(socket, id, action) do
    with {:ok, %{} = member} <- Accounts.member(id, options(socket)),
         :ok <- done(action.(member, options(socket))) do
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
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Members
        <:subtitle>The people of {@organisation.name}</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <Cinder.collection
        id="members"
        query={Accounts.query_to_members(%{}, actor: @current_user, tenant: @organisation)}
        actor={@current_user}
        tenant={@organisation}
      >
        <:col :let={member} field="email" label="Email address">{member.email}</:col>
        <:col :let={member} field="role" label="Role" filter sort>{role_word(member.role)}</:col>
        <:col :let={member} field="id" label="Actions">
          <.button
            :if={member.role == :member and Accounts.role_can?(@role, :make_administrator, member)}
            phx-click="make_administrator"
            phx-value-id={member.id}
            aria-label={"Make #{member.email} an administrator"}
          >
            Make administrator
          </.button>
          <.button
            :if={Accounts.role_can?(@role, :remove, member)}
            phx-click="remove"
            phx-value-id={member.id}
            aria-label={"Remove #{member.email} from #{@organisation.name}"}
          >
            Remove
          </.button>
        </:col>
      </Cinder.collection>

      <section :if={@can_invite?} aria-labelledby="invite-heading">
        <h2 id="invite-heading">Invite a person</h2>
        <.form for={@invite_form} id="invite" phx-submit="invite">
          <.input field={@invite_form[:email]} type="email" label="Email address" required />
          <.input
            :if={@can_invite_administrator?}
            field={@invite_form[:role]}
            type="select"
            label="Role"
            options={[{"Member", "member"}, {"Administrator", "administrator"}]}
          />
          <footer>
            <.button type="submit">Send the invitation</.button>
          </footer>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  defp role_word(:administrator), do: "Administrator"
  defp role_word(:member), do: "Member"
end
