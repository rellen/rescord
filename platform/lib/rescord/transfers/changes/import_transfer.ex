defmodule Rescord.Transfers.Changes.ImportTransfer do
  @moduledoc """
  Reads a transfer file from a partner on another server into a transfer
  that waits for an answer (ADR 0043).

  After the policy, the change reads the file with the keys of this refuge
  (`Rescord.Transfers.Archive.read/4`). The file opens only when a partner
  that this refuge recorded, and has not ended, signed it, and only when it
  is for this refuge. The change gives the transfer the clean copy, the
  partner and the id of the export, so a second import of one file is
  refused. After the write, in the transaction, it puts the files of the
  copy in the store of this refuge.
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
      :to_organisation_id,
      Changeset.get_argument(changeset, :organisation_id)
    )
    |> Changeset.force_change_attribute(:sent_by_id, SendTransfer.user_id(context.actor))
    |> Changeset.before_action(&import_file/1)
  end

  defp import_file(changeset) do
    to_id = Changeset.get_attribute(changeset, :to_organisation_id)
    organisation = Accounts.organisation_of("org_" <> to_id)
    file = Changeset.get_argument(changeset, :file)

    case Archive.read(file, organisation.id, Keys.of(organisation), &partner(to_id, &1)) do
      {:ok, partner, transfer, files} ->
        changeset
        |> Changeset.force_change_attribute(:remote_partner_id, partner.id)
        |> Changeset.force_change_attribute(:export_id, transfer["export_id"])
        |> Changeset.force_change_attribute(:resident_name, transfer["resident_name"])
        |> Changeset.force_change_attribute(:note, transfer["note"])
        |> Changeset.force_change_attribute(:parts, transfer["parts"])
        |> Changeset.force_change_attribute(:snapshot, transfer["copy"])
        |> Changeset.after_action(fn _changeset, record ->
          case Files.store(Map.to_list(files), record.to_organisation_id, record.id) do
            :ok ->
              {:ok, record}

            {:error, _error} ->
              {:error,
               Ash.Error.Changes.InvalidArgument.exception(
                 field: :file,
                 message: "has a file that did not reach the store. Try again later"
               )}
          end
        end)

      {:error, words} ->
        Changeset.add_error(changeset, field: :file, message: words)
    end
  end

  defp partner(to_id, refuge_id) when is_binary(refuge_id) do
    with {:ok, refuge_id} <- Ecto.UUID.cast(refuge_id) do
      RemotePartner
      |> Ash.Query.filter(
        organisation_id == ^to_id and refuge_id == ^refuge_id and state == :active
      )
      |> Ash.read_one!(authorize?: false)
    else
      :error -> nil
    end
  end

  defp partner(_to_id, _refuge_id), do: nil
end
