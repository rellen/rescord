defmodule Rescord.Expenses.Changes.StoreReceipt do
  @moduledoc """
  Gives a new receipt its type, its size and its keys, and puts its file in
  the store after the write (ADR 0082), as
  `Rescord.Journal.Changes.StoreAttachment` does for the journal.

  `Rescord.Storage.Upload.prepare/1` checks the file and makes a photo safe
  to keep, and `Rescord.Storage.Scan.check/1` scans a PDF when the scan is
  on (issue 37). The keys are `<organisation id>/receipts/<receipt id>` and, for a
  photo, `<organisation id>/thumbnails/<receipt id>`.

  The files go into the store in an `after_action` hook, in the
  transaction: a fault of the store returns an error, and the record is not
  written.
  """

  use Ash.Resource.Change

  alias Rescord.{Accounts, Storage}
  alias Rescord.Storage.{Scan, Upload}

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :content) do
      content when is_binary(content) ->
        # A PDF goes to the virus scan when it is on (issue 37).
        with {:ok, files} <- Upload.prepare(content),
             :ok <- Scan.check(files) do
          store(changeset, files)
        else
          {:error, error} -> Ash.Changeset.add_error(changeset, %{error | field: :content})
        end

      _none ->
        changeset
    end
  end

  defp store(changeset, files) do
    # The id is not set when a change runs, and the keys name it.
    id = Ash.Changeset.get_attribute(changeset, :id) || Ash.UUID.generate()
    organisation = Accounts.organisation_of(changeset.to_tenant)
    key = Storage.key(organisation.id, ["receipts", id])
    thumbnail_key = files.thumbnail && Storage.key(organisation.id, ["thumbnails", id])

    changeset
    |> Ash.Changeset.force_change_attribute(:id, id)
    |> Ash.Changeset.force_change_attribute(:content_type, files.content_type)
    |> Ash.Changeset.force_change_attribute(:size, byte_size(files.bytes))
    |> Ash.Changeset.force_change_attribute(:key, key)
    |> Ash.Changeset.force_change_attribute(:thumbnail_key, thumbnail_key)
    |> Ash.Changeset.after_action(fn _changeset, receipt ->
      case Upload.put(key, thumbnail_key, files) do
        :ok ->
          {:ok, receipt}

        {:error, _reason} ->
          {:error,
           Ash.Error.Changes.InvalidArgument.exception(
             field: :content,
             message: "did not reach the store. Try again later"
           )}
      end
    end)
  end
end
