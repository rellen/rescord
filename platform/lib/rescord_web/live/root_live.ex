defmodule RescordWeb.RootLive do
  @moduledoc """
  The page of a root user: the organisations, and the root users.

  A root user creates an organisation here, which makes its schema, and makes
  another user a root user. The live session lets only a root user in.
  """

  use RescordWeb, :live_view

  import RescordWeb.AccountComponents

  alias Rescord.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Root", problems: [], time_zones: Accounts.time_zones())
     |> assign_organisation_form(%{"name" => "", "short_name" => "", "time_zone" => ""})
     |> assign(root_form: to_form(%{"email" => ""}, as: :root))
     |> assign_roots()}
  end

  defp assign_organisation_form(socket, params) do
    assign(socket, organisation_form: typed_form(params, as: :organisation))
  end

  defp assign_roots(socket) do
    assign(socket, roots: Accounts.roots!(actor: socket.assigns.current_user))
  end

  @impl true
  def handle_event("create_organisation", %{"organisation" => params}, socket)
      when is_map(params) do
    attributes = %{
      name: params["name"],
      short_name: params["short_name"],
      time_zone: params["time_zone"]
    }

    case Accounts.create_organisation(attributes, actor: socket.assigns.current_user) do
      {:ok, organisation} ->
        {:noreply,
         socket
         |> assign(problems: [])
         |> assign_organisation_form(%{"name" => "", "short_name" => "", "time_zone" => ""})
         |> put_flash(:info, "#{organisation.name} is created.")
         |> Cinder.Refresh.refresh_table("organisations")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(problems: Accounts.error_messages(error))
         |> assign_organisation_form(params)}
    end
  end

  def handle_event("make_root", %{"root" => %{"email" => address}}, socket)
      when is_binary(address) do
    actor = socket.assigns.current_user

    with {:ok, %{} = user} <- Accounts.user_by_email(address, actor: actor),
         {:ok, _root} <- Accounts.make_root(user, actor: actor) do
      RescordWeb.UserAuth.disconnect(user.id)

      {:noreply,
       socket
       |> assign(problems: [], root_form: to_form(%{"email" => ""}, as: :root))
       |> put_flash(:info, "#{address} is a root user now.")
       |> assign_roots()}
    else
      {:ok, nil} ->
        {:noreply, assign(socket, problems: ["No user has the address #{address}"])}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event("revoke_root", %{"id" => id}, socket) when is_binary(id) do
    actor = socket.assigns.current_user

    with %{} = root <- Enum.find(socket.assigns.roots, &(&1.id == id)),
         {:ok, _user} <- Accounts.revoke_root(root, actor: actor) do
      # Each open page of that user has the user as a root user still.
      RescordWeb.UserAuth.disconnect(root.id)
      {:noreply, socket |> assign(problems: []) |> assign_roots()}
    else
      {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
      nil -> {:noreply, socket}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <.header>
        Root
        <:subtitle>The organisations of Rescord, and the users who manage Rescord itself.</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p><a href={~p"/root/lists"}>See the shared lists of values</a>.</p>

      <.organisations
        current_user={@current_user}
        organisation_form={@organisation_form}
        time_zones={@time_zones}
      />

      <.root_users roots={@roots} current_user={@current_user} root_form={@root_form} />

      <p>This server runs Rescord {Rescord.version()}.</p>
    </Layouts.app>
    """
  end
end
