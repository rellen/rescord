defmodule RescordWeb.RootPrivacyLive do
  @moduledoc """
  Privacy of the server, for a root user, at `/root/privacy` (ADR 0105):
  what the privacy notices say about the server, and the erasure of an
  account on request. The live session lets only a root user in.

  A person asks the operator to erase their account, by the contact of the
  notice of the server. The root user types the address, how the request
  came and how they checked who asked, and chooses once for every
  organisation whether the comments of the person stay (issue 31, call 7).
  Each organisation where the person was a member gets a closed request
  that says so. A root user is never erased.
  """

  use RescordWeb, :live_view

  alias Rescord.{Accounts, Privacy}
  alias RescordWeb.PrivacyWords

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Privacy of the server", problems: [])
     |> assign(erase_form: erase_form())
     |> assign_settings()}
  end

  defp erase_form,
    do:
      to_form(%{"email" => "", "how_received" => "email", "identity" => "", "sure" => "false"},
        as: :account
      )

  defp assign_settings(socket) do
    server = Privacy.instance_settings()

    form =
      to_form(
        %{
          "operator_name" => server.operator_name || "",
          "operator_contact" => server.operator_contact || "",
          "hosting" => server.hosting || "",
          "mail_provider" => server.mail_provider || "",
          "backup_days" => to_string(server.backup_days)
        },
        as: :server
      )

    assign(socket, server: server, settings_form: form)
  end

  @impl true
  def handle_event("save", %{"server" => params}, socket) when is_map(params) do
    fields =
      params
      |> Map.take(~w(operator_name operator_contact hosting mail_provider backup_days))
      |> Map.new(fn {key, value} -> {key, if(value == "", do: nil, else: value)} end)

    case Privacy.save_instance_settings(fields, actor: socket.assigns.current_user) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> assign(problems: [])
         |> assign_settings()
         |> put_flash(:info, "The settings of privacy of the server are saved.")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event(
        "erase",
        %{"account" => %{"sure" => "true", "email" => email} = params},
        socket
      )
      when is_binary(email) do
    choices = %{
      keep_comments: params["comments"] == "keep",
      how_received: way(params["how_received"]),
      identity: params["identity"]
    }

    with {:ok, %{} = user} <- Accounts.user_by_email(String.trim(email), authorize?: false),
         :ok <- Privacy.erase_account(user, choices, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(problems: [], erase_form: erase_form())
       |> put_flash(:info, "The account is erased.")}
    else
      {:ok, nil} ->
        {:noreply, assign(socket, problems: ["No account has that email address"])}

      {:error, :root} ->
        {:noreply, assign(socket, problems: ["A root user is never erased: revoke root first"])}

      {:error, :closed} ->
        {:noreply, assign(socket, problems: ["The account is erased already"])}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event("erase", _params, socket),
    do: {:noreply, assign(socket, problems: ["Tick the box to say that you understand"])}

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp way(text) do
    Enum.find_value([:email, :letter, :in_person], :email, &(to_string(&1) == text && &1))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <.header>
        Privacy of the server
        <:subtitle>
          What the privacy notices say about this server, and the erasure of an account.
          The notice of the server is at <.link href={~p"/privacy"}>{url(~p"/privacy")}</.link>.
        </:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section id="server-settings" aria-labelledby="server-heading">
        <h2 id="server-heading">What the notices say about the server</h2>
        <.form for={@settings_form} id="server" phx-submit="save">
          <.input
            field={@settings_form[:operator_name]}
            type="text"
            label="Who runs this server"
            maxlength="200"
          />
          <.input
            field={@settings_form[:operator_contact]}
            type="text"
            label="Where a person writes to the operator about their account"
            maxlength="254"
          />
          <.input
            field={@settings_form[:hosting]}
            type="text"
            label="Where the servers and the files are: the country and the provider"
            maxlength="200"
          />
          <.input
            field={@settings_form[:mail_provider]}
            type="text"
            label="The provider that sends the email"
            maxlength="200"
          />
          <.input
            field={@settings_form[:backup_days]}
            type="number"
            label="The days that a backup keeps a dump (RESCORD_BACKUP_KEEP_DAYS)"
            min="1"
            max="3650"
            required
          />
          <footer><.button type="submit">Save</.button></footer>
        </.form>
      </section>

      <section id="erase-account" aria-labelledby="erase-account-heading">
        <h2 id="erase-account-heading">Erase an account on request</h2>
        <p>
          The person becomes "Former member" and a number in each organisation where they were
          a member, and the account loses its email address, its sign-ins and its devices. The
          records that they wrote about the animals stay. The money records of each
          organisation keep their email for its money period. Take root away from a root user
          first. A member who is the last one able to change the members of an organisation
          stays until another person can.
        </p>
        <.form for={@erase_form} id="erase-account-form" phx-submit="erase">
          <.input
            field={@erase_form[:email]}
            type="email"
            label="The email address of the account"
            required
          />
          <.input
            field={@erase_form[:how_received]}
            type="select"
            label="How the request came"
            options={PrivacyWords.way_options()}
          />
          <.input
            field={@erase_form[:identity]}
            type="text"
            label="How you checked who asked"
            maxlength="300"
            required
          />
          <fieldset>
            <legend>Their comments, in every organisation</legend>
            <label>
              <input type="radio" name="account[comments]" value="delete" checked /> Delete them
            </label>
            <label>
              <input type="radio" name="account[comments]" value="keep" />
              Keep them, signed Former member and a number
            </label>
          </fieldset>
          <.input
            field={@erase_form[:sure]}
            type="checkbox"
            label="I understand that an erasure cannot be undone"
            required
          />
          <footer><.button type="submit">Erase the account</.button></footer>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
