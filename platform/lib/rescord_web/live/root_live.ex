defmodule RescordWeb.RootLive do
  @moduledoc """
  The page of a root user: the organisations, and the root users.

  A root user creates an organisation here, which makes its schema, and makes
  another user a root user. The live session lets only a root user in.
  """

  use RescordWeb, :live_view

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
    assign(socket, organisation_form: to_form(params, as: :organisation))
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
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Root
        <:subtitle>The organisations of Rescord, and the users who manage Rescord itself.</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <p><a href={~p"/root/lists"}>See the shared lists of values</a>.</p>

      <section aria-labelledby="organisations-heading">
        <h2 id="organisations-heading">Organisations</h2>

        <Cinder.collection
          id="organisations"
          query={Accounts.query_to_organisations(%{}, actor: @current_user)}
          actor={@current_user}
        >
          <:col :let={organisation} field="name" label="Name" filter sort>
            <a href={~p"/o/#{organisation.short_name}/members"}>{organisation.name}</a>
          </:col>
          <:col :let={organisation} field="time_zone" label="Time zone" sort>
            {organisation.time_zone}
          </:col>
          <:col :let={organisation} field="short_name" label="Short name" sort>
            {organisation.short_name}
          </:col>
        </Cinder.collection>

        <.form for={@organisation_form} id="new-organisation" phx-submit="create_organisation">
          <h3>New organisation</h3>
          <.input field={@organisation_form[:name]} label="Name" required />
          <.input
            field={@organisation_form[:short_name]}
            label="Short name, for the address of its pages"
            required
          />
          <.input
            field={@organisation_form[:time_zone]}
            label="Time zone, for example Australia/Brisbane"
            list="time-zones"
            autocomplete="off"
            required
          />
          <datalist id="time-zones">
            <option :for={zone <- @time_zones} value={zone}></option>
          </datalist>
          <footer>
            <.button type="submit">Create the organisation</.button>
          </footer>
        </.form>
      </section>

      <section aria-labelledby="roots-heading">
        <h2 id="roots-heading">Root users</h2>

        <ul>
          <li :for={root <- @roots}>
            {root.email}
            <.button
              :if={root.id != @current_user.id}
              phx-click="revoke_root"
              phx-value-id={root.id}
              aria-label={"Make #{root.email} an ordinary user"}
            >
              Make an ordinary user
            </.button>
          </li>
        </ul>

        <.form for={@root_form} id="new-root" phx-submit="make_root">
          <h3>Make a user a root user</h3>
          <.input field={@root_form[:email]} type="email" label="Email address of the user" required />
          <footer>
            <.button type="submit">Make a root user</.button>
          </footer>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
