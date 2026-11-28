defmodule RescordWeb.PartnersLive do
  @moduledoc """
  The partner refuges of an organisation, at `/o/<short name>/partners`
  (ADR 0042).

  Each member reads the partnerships of the organisation. A person whose
  role has the power `:transfers` asks a refuge by its short name, accepts
  or declines a question from another refuge, and ends a partnership. The
  page lists no other refuge: a person names a refuge that they know.

  A refuge on another Rescord server is a partner through its partner card
  (ADR 0043): the person with the power records the card of the other
  refuge, gives the card of this one, and the two read the fingerprint to
  each other before the first file.

  The page acts only on a partnership that it has in hand, and reads only
  the fields that it knows from what the browser sends.
  """

  use RescordWeb, :live_view

  import RescordWeb.TransferComponents

  alias Rescord.{Accounts, Transfers}

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.role

    {:ok,
     socket
     # A request of another refuge, and its answer, show at once (ADR 0096).
     |> LiveChanges.listen([Transfers], &assign_partnerships/1)
     |> assign(
       page_title: "Partner refuges",
       problems: [],
       can_ask?: Transfers.role_can?(role, :partnership, :ask),
       can_answer?: Transfers.role_can?(role, :partnership, :accept),
       can_end?: Transfers.role_can?(role, :partnership, :end),
       can_record?: Transfers.role_can?(role, :remote_partner, :record),
       can_end_remote?: Transfers.role_can?(role, :remote_partner, :end)
     )
     |> assign_partnerships()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_partnerships(socket) do
    {:ok, partnerships} =
      Transfers.partnerships_of(socket.assigns.organisation, actor: socket.assigns.current_user)

    {:ok, remote} =
      Transfers.remote_partners_of(socket.assigns.organisation,
        actor: socket.assigns.current_user
      )

    # Only a person who records a partner needs the card of this refuge.
    {card, fingerprint} =
      if socket.assigns.can_record?,
        do: Transfers.card(socket.assigns.organisation),
        else: {nil, nil}

    assign(socket,
      partnerships: partnerships,
      remote: remote,
      card: card,
      fingerprint: fingerprint
    )
  end

  defp path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/partners"

  @impl true
  def handle_event("ask", %{"partner" => %{"short_name" => short_name}}, socket)
      when is_binary(short_name) do
    case Transfers.ask_partner(socket.assigns.organisation, short_name, options(socket)) do
      {:ok, _partnership} ->
        {:noreply,
         socket
         |> put_flash(:info, "The question is with that refuge.")
         |> push_navigate(to: path(socket))}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event(event, %{"id" => id}, socket)
      when event in ["accept", "decline", "end"] and is_binary(id) do
    action =
      case event do
        "accept" -> &Transfers.accept_partner/2
        "decline" -> &Transfers.decline_partner/2
        "end" -> &Transfers.end_partnership/2
      end

    with %{} = partnership <- Enum.find(socket.assigns.partnerships, &(&1.id == id)),
         {:ok, _partnership} <- action.(partnership, actor: socket.assigns.current_user) do
      {:noreply, push_navigate(socket, to: path(socket))}
    else
      nil ->
        {:noreply, socket}

      {:error, error} ->
        {:noreply,
         socket |> assign(problems: Accounts.error_messages(error)) |> assign_partnerships()}
    end
  end

  def handle_event("record", %{"remote" => %{"card" => card}}, socket) when is_binary(card) do
    case Transfers.record_remote_partner(socket.assigns.organisation, card, options(socket)) do
      {:ok, partner} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{partner.name} is a partner on another server now.")
         |> push_navigate(to: path(socket))}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event("end_remote", %{"id" => id}, socket) when is_binary(id) do
    with %{} = partner <- Enum.find(socket.assigns.remote, &(&1.id == id)),
         {:ok, _partner} <-
           Transfers.end_remote_partner(partner, actor: socket.assigns.current_user) do
      {:noreply, push_navigate(socket, to: path(socket))}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header icon={Icons.section(:partners)}>
        Partner refuges
        <:subtitle>The refuges that {@organisation.name} transfers residents with</:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/transfers"} data-variant="secondary">
            <.icon name="arrows-right-left" /> The transfers
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <.partnerships
        partnerships={@partnerships}
        organisation={@organisation}
        can_answer?={@can_answer?}
        can_end?={@can_end?}
      />

      <.ask_form :if={@can_ask?} />

      <.remote_partners
        remote={@remote}
        card={@card}
        fingerprint={@fingerprint}
        can_record?={@can_record?}
        can_end?={@can_end_remote?}
      />
    </Layouts.app>
    """
  end
end
