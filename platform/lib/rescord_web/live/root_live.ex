defmodule RescordWeb.RootLive do
  @moduledoc """
  The page of a root user: the organisations, and the root users, with a
  line for the assistant (ADR 0069).

  A root user creates an organisation here, which makes its schema, and makes
  another user a root user. The live session lets only a root user in.
  """

  use RescordWeb, :live_view
  use Cinder.UrlSync

  import RescordWeb.AccountComponents
  import RescordWeb.RubyComponents, only: [root_line: 1]

  alias Rescord.{Accounts, Ruby}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Root", problems: [], time_zones: Accounts.time_zones())
     |> assign_organisation_form(new_organisation())
     |> assign(root_form: to_form(%{"email" => ""}, as: :root))
     |> assign(providers: Ruby.providers!(actor: socket.assigns.current_user))
     |> assign(usage_mode: Rescord.Usage.settings(actor: socket.assigns.current_user).mode)
     |> assign_roots()}
  end

  # The fields of the form of a new organisation, with the default locale
  # chosen (ADR 0075).
  defp new_organisation do
    %{"name" => "", "short_name" => "", "time_zone" => "", "locale" => Accounts.default_locale()}
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
      time_zone: params["time_zone"],
      locale: params["locale"] || Accounts.default_locale()
    }

    case Accounts.create_organisation(attributes, actor: socket.assigns.current_user) do
      {:ok, organisation} ->
        {:noreply,
         socket
         |> assign(problems: [])
         |> assign_organisation_form(new_organisation())
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
      <.header icon={Icons.section(:root)}>
        Root
        <:subtitle>The organisations of Rescord, and the users who manage Rescord itself.</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p><.link navigate={~p"/root/lists"}>See the shared lists of values</.link>.</p>
      <p><.link navigate={~p"/root/push"}>Set the notifications on devices and ntfy</.link>.</p>
      <p>
        <.link navigate={~p"/root/privacy"}>Privacy of the server</.link>: what the notices say
        about it, and the erasure of an account.
      </p>
      <p><a href={~p"/root/oban"}>Watch the background jobs, in Oban Web</a>.</p>
      <.root_line providers={@providers} />
      <p id="usage-line">
        Usage counts: {RescordWeb.UsageWords.mode(@usage_mode)}. <a href={~p"/root/usage"}>See the counts, and where they go</a>.
      </p>

      <.organisations
        current_user={@current_user}
        organisation_form={@organisation_form}
        time_zones={@time_zones}
        url_state={@url_state}
      />

      <.root_users roots={@roots} current_user={@current_user} root_form={@root_form} />

      <p>This server runs Rescord {Rescord.version()}.</p>
    </Layouts.app>
    """
  end
end
