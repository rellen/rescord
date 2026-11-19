defmodule Rescord.Transfers.Changes.ExportTransfer do
  @moduledoc """
  Gives a new export its refuge, its partner on another server, its copy,
  and the transfer file (ADR 0043).

  After the policy, the change refuses a partner that this refuge did not
  record or ended, and takes the copy as a send does
  (`Rescord.Transfers.Changes.SendTransfer.take_copy/3`). After the write,
  it reads the files of the copy, writes the file
  (`Rescord.Transfers.Archive.write/4`), signed with the key of this refuge
  and encrypted for the partner, and puts it in the metadata of the record
  under `:file`. The record keeps the state `exported`, and no file.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Ash.Changeset
  alias Rescord.Accounts
  alias Rescord.Transfers.{Archive, Files, Keys, RemotePartner}
  alias Rescord.Transfers.Changes.SendTransfer

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Changeset.force_change_attribute(
      :from_organisation_id,
      Changeset.get_argument(changeset, :organisation_id)
    )
    |> Changeset.force_change_attribute(:state, :exported)
    |> Changeset.force_change_attribute(:sent_by_id, SendTransfer.user_id(context.actor))
    |> Changeset.before_action(&export(&1, context.actor))
  end

  defp export(changeset, actor) do
    from_id = Changeset.get_attribute(changeset, :from_organisation_id)
    partner_id = Changeset.get_argument(changeset, :remote_partner_id)

    case partner(from_id, partner_id) do
      %RemotePartner{} = partner ->
        changeset
        |> Changeset.force_change_attribute(:remote_partner_id, partner.id)
        |> SendTransfer.take_copy(actor, from_id)
        |> Changeset.after_action(&write(&1, &2, partner))

      nil ->
        Changeset.add_error(changeset,
          field: :remote_partner_id,
          message: "is not a partner of this refuge on another server"
        )
    end
  end

  defp partner(from_id, partner_id) do
    RemotePartner
    |> Ash.Query.filter(id == ^partner_id and organisation_id == ^from_id and state == :active)
    |> Ash.read_one!(authorize?: false)
  end

  defp write(changeset, transfer, partner) do
    organisation = Accounts.organisation_of("org_" <> transfer.from_organisation_id)

    case Files.read(changeset.context[:sources] || []) do
      {:ok, files} ->
        file =
          Archive.write(
            %{
              "export_id" => transfer.id,
              "from_refuge" => organisation.id,
              "from_name" => organisation.name,
              "to_refuge" => partner.refuge_id,
              "resident_name" => transfer.resident_name,
              "parts" => Enum.map(transfer.parts, &Atom.to_string/1),
              "note" => transfer.note,
              "sent_at" => DateTime.to_iso8601(transfer.sent_at),
              "copy" => transfer.snapshot
            },
            files,
            Keys.of(organisation),
            partner
          )

        {:ok, Ash.Resource.put_metadata(transfer, :file, file)}

      {:error, _error} ->
        {:error,
         Ash.Error.Changes.InvalidArgument.exception(
           field: :resident_id,
           message: "has a file that the store did not give. Try again later"
         )}
    end
  end
end
