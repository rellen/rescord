defmodule RescordWeb.TransfersLive do
  @moduledoc """
  The transfers of an organisation, at `/o/<short name>/transfers`
  (ADR 0042), and one copy, at `/o/<short name>/transfers/<id>`.

  The page lists the transfers that the organisation received and sent. A
  person whose role has the power `:transfers` sends a resident to a
  partner refuge, with the parts of the copy that they choose; the setting
  of the organisation ticks the parts at first. That person also accepts
  or declines a transfer that waits for an answer, and withdraws one that
  the organisation sent. Each member reads a copy that the organisation
  accepted.

  The files of a transfer to a partner on this server go in a job after
  the send (ADR 0100). While they do, the list of the sent transfers says
  "Sending", with how many files are there. A transfer whose files did not
  arrive says "Not sent" and why, with "Send again" and "Withdraw".

  With a partner on another server (ADR 0043), the person with the power
  writes a transfer file through `RescordWeb.TransferFileController`, and
  imports a file from such a partner here: it waits for an answer, as a
  transfer on this server does.

  The page reads again when a transfer or a partner changes (ADR 0096), so
  a transfer that arrives, and the answer of the other refuge, show at
  once.

  The page acts only on a transfer that it has in hand, and reads only the
  fields that it knows from what the browser sends: a part comes from
  `RescordWeb.TransferWords.part_of/1`, which makes no atom.
  """

  use RescordWeb, :live_view

  import RescordWeb.TransferComponents

  alias Rescord.{Accounts, Residents, Transfers}
  alias RescordWeb.TransferWords
  alias RescordWeb.Widgets.Comments

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.role

    {:ok,
     socket
     |> LiveChanges.listen([Transfers], &read_again/1)
     |> assign(
       problems: [],
       can_send?: Transfers.role_can?(role, :transfer, :send),
       can_answer?: Transfers.role_can?(role, :transfer, :accept),
       can_withdraw?: Transfers.role_can?(role, :transfer, :withdraw),
       can_send_again?: Transfers.role_can?(role, :transfer, :send_again),
       can_export?: Transfers.role_can?(role, :transfer, :export),
       can_import?: Transfers.role_can?(role, :transfer, :import)
     )
     |> allow_file()}
  end

  # The transfer file of an import, for a person who imports one.
  defp allow_file(%{assigns: %{can_import?: true}} = socket) do
    allow_upload(socket, :transfer_file,
      # A `.rescord` file has no MIME type, and the import reads the file
      # itself: a file that is not one is refused in words.
      accept: :any,
      max_entries: 1,
      max_file_size: Transfers.max_file_size()
    )
  end

  defp allow_file(socket), do: socket

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = transfer} <-
           Transfers.transfer_of(socket.assigns.organisation, id,
             actor: socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> assign(
         page_title: "Transfer of #{transfer.resident_name || "a resident"}",
         transfer: transfer
       )
       |> Comments.assign_widget(:comments, {:transfer, transfer.id})}
    else
      _no_transfer -> {:noreply, push_navigate(socket, to: path(socket))}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket |> assign(page_title: "Transfers", transfer: nil) |> assign_lists()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # After a change of another person (ADR 0096): the copy that the page
  # shows, or the lists. The form to send keeps what the person chose.
  defp read_again(%{assigns: %{transfer: %{id: id}}} = socket) do
    case Transfers.transfer_of(socket.assigns.organisation, id,
           actor: socket.assigns.current_user
         ) do
      {:ok, %{} = transfer} -> assign(socket, transfer: transfer)
      _no_transfer -> socket
    end
  end

  defp read_again(socket), do: assign_transfers(socket)

  defp assign_lists(socket) do
    parts = Enum.map(socket.assigns.organisation.transfer_parts, &Atom.to_string/1)

    socket
    |> assign_transfers()
    |> assign(send_form: to_form(%{"parts" => parts}, as: :transfer))
  end

  defp assign_transfers(socket) do
    organisation = socket.assigns.organisation
    actor = [actor: socket.assigns.current_user]
    {:ok, transfers} = Transfers.transfers_of(organisation, actor)
    {:ok, partners} = Transfers.partners_of(organisation, actor)

    {:ok, remote} = Transfers.remote_partners_of(organisation, actor)

    residents =
      if socket.assigns.can_send? or socket.assigns.can_export? do
        {:ok, residents} = Residents.residents([load: [:name]] ++ options(socket))
        residents |> Enum.map(&{&1.name || "A resident with no name", &1.id}) |> Enum.sort()
      else
        []
      end

    {received, sent} = Enum.split_with(transfers, &(&1.to_organisation_id == organisation.id))

    assign(socket,
      received: received,
      sent: sent,
      partners: partners,
      remote: for(%{state: :active} = partner <- remote, do: {partner.name, partner.id}),
      residents: residents
    )
  end

  defp path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/transfers"

  @impl true
  def handle_event("send", %{"transfer" => fields}, socket) when is_map(fields) do
    parts =
      for text <- List.wrap(fields["parts"]),
          {:ok, part} <- [TransferWords.part_of(text)],
          uniq: true,
          do: part

    facts = %{
      organisation_id: socket.assigns.organisation.id,
      partner_id: offered(socket.assigns.partners, fields["partner_id"]),
      resident_id: offered(socket.assigns.residents, fields["resident_id"]),
      parts: parts,
      note: non_blank(fields["note"])
    }

    case Transfers.send_transfer(facts, actor: socket.assigns.current_user) do
      {:ok, transfer} ->
        {:noreply,
         socket
         |> put_flash(:info, sent_words(transfer))
         |> push_navigate(to: path(socket))}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           send_form: typed_form(fields, as: :transfer)
         )}
    end
  end

  def handle_event("choose_file", _params, socket), do: {:noreply, socket}

  def handle_event("import", _params, %{assigns: %{can_import?: true}} = socket) do
    files =
      consume_uploaded_entries(socket, :transfer_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case files do
      [file] ->
        case Transfers.import_transfer(socket.assigns.organisation, file,
               actor: socket.assigns.current_user
             ) do
          {:ok, transfer} ->
            {:noreply,
             socket
             |> put_flash(:info, "The transfer of #{transfer.resident_name} waits for an answer.")
             |> push_navigate(to: path(socket))}

          {:error, error} ->
            {:noreply,
             socket |> assign(problems: Accounts.error_messages(error)) |> assign_lists()}
        end

      [] ->
        {:noreply, assign(socket, problems: ["Choose a transfer file first."])}
    end
  end

  def handle_event(event, %{"id" => id}, socket)
      when event in ["accept", "decline", "withdraw", "send_again", "check_again"] and
             is_binary(id) do
    action =
      case event do
        "accept" -> &Transfers.accept_transfer/2
        "decline" -> &Transfers.decline_transfer/2
        "withdraw" -> &Transfers.withdraw_transfer/2
        "send_again" -> &Transfers.send_transfer_again/2
        "check_again" -> &Transfers.check_transfer_again/2
      end

    with %{} = transfer <-
           Enum.find(socket.assigns.received ++ socket.assigns.sent, &(&1.id == id)),
         {:ok, _transfer} <- action.(transfer, actor: socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:info, answer_words(event, transfer))
       |> push_navigate(to: path(socket))}
    else
      nil ->
        {:noreply, socket}

      {:error, error} ->
        {:noreply, socket |> assign(problems: Accounts.error_messages(error)) |> assign_lists()}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # What a press on a transfer did, as the message of the page (issue 35).
  defp answer_words("accept", transfer),
    do: "The transfer of #{transfer.resident_name} is accepted."

  defp answer_words("decline", transfer),
    do: "The transfer of #{transfer.resident_name} is declined."

  defp answer_words("withdraw", transfer),
    do: "The transfer of #{transfer.resident_name} is withdrawn."

  defp answer_words("send_again", transfer),
    do: "The transfer of #{transfer.resident_name} is sent again."

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # A transfer with files is on its way: a job copies them after the send
  # (ADR 0100), and this page hears when it is there.
  defp sent_words(%{state: :sending}),
    do: "The copy is on its way. The partner refuge sees it when each file is there."

  defp sent_words(_sent), do: "The copy is with the partner refuge."

  # The id of an option that the page offered, or `nil`, which the action
  # refuses.
  defp offered(options, id) do
    if Enum.any?(options, fn {_name, option_id} -> option_id == id end), do: id
  end

  @impl true
  def render(%{transfer: %{}} = assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:home}
    >
      <.copy transfer={@transfer} organisation={@organisation} />
      <Comments.render state={@comments} record="this transfer" partner? />
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:home}
    >
      <.header icon={Icons.section(:transfers)}>
        <:crumb navigate={~p"/o/#{@organisation.short_name}"}>{@organisation.name}</:crumb>
        Transfers
        <:subtitle>The residents that {@organisation.name} sent and received</:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/partners"} data-variant="secondary">
            <.icon name="link" /> Partner refuges
          </.link>
        </:actions>
      </.header>

      <.problems list={@problems} />

      <.transfers_table
        id="received"
        title="Received"
        empty="No partner refuge has sent you a resident yet. When one does, it waits here for your answer."
        transfers={@received}
        organisation={@organisation}
        can_answer?={@can_answer?}
        can_withdraw?={false}
      />

      <.transfers_table
        id="sent"
        title="Sent"
        empty="You have sent no resident yet."
        transfers={@sent}
        organisation={@organisation}
        can_answer?={false}
        can_withdraw?={@can_withdraw?}
        can_send_again?={@can_send_again?}
      />

      <.send_form
        :if={@can_send?}
        form={@send_form}
        partners={@partners}
        residents={@residents}
      />

      <.export_form
        :if={@can_export?}
        organisation={@organisation}
        remote={@remote}
        residents={@residents}
        parts={@organisation.transfer_parts}
      />

      <.import_form :if={@can_import?} upload={@uploads.transfer_file} />
    </Layouts.app>
    """
  end
end
