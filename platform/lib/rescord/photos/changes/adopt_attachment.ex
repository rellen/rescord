defmodule Rescord.Photos.Changes.AdoptAttachment do
  @moduledoc """
  Makes a photo of a journal entry a photo of its resident (ADR 0055).

  The change reads the attachment and its entry with the grants of the
  actor, as of the instant of the action. The photo takes the resident of
  the entry, the date of the entry in the time zone of the organisation,
  and the type, the size and the keys of the files of the attachment: the
  two records name the same files, and Rescord makes no copy.

  It refuses an attachment that the actor cannot read, one that is not
  there, and a PDF. With no user, it does nothing: the policy then refuses
  the action, with the answer that it gives each person who is not signed
  in.
  """

  use Ash.Resource.Change

  alias Rescord.{Accounts, Journal}

  # The change reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, %{actor: %Accounts.User{} = actor}) do
    id = Ash.Changeset.get_argument(changeset, :attachment_id)
    options = options(changeset, actor)

    with true <- is_binary(id),
         {:ok, %{} = attachment} <- Journal.attachment(id, options),
         true <- String.starts_with?(attachment.content_type, "image/"),
         {:ok, %{} = entry} <- Journal.entry(attachment.entry_id, options) do
      organisation = Accounts.organisation_of(changeset.to_tenant)

      changeset
      |> Ash.Changeset.force_change_attribute(:attachment_id, attachment.id)
      |> Ash.Changeset.force_change_attribute(:resident_id, entry.resident_id)
      |> Ash.Changeset.force_change_attribute(:content_type, attachment.content_type)
      |> Ash.Changeset.force_change_attribute(:size, attachment.size)
      |> Ash.Changeset.force_change_attribute(:key, attachment.key)
      |> Ash.Changeset.force_change_attribute(:thumbnail_key, attachment.thumbnail_key)
      |> Ash.Changeset.force_change_attribute(
        :taken_on,
        Accounts.local_date(organisation, entry.happened_at)
      )
    else
      _no_photo ->
        Ash.Changeset.add_error(changeset,
          field: :attachment_id,
          message: "is not a photo of a journal entry"
        )
    end
  end

  def change(changeset, _opts, _context), do: changeset

  defp options(changeset, actor) do
    base = [actor: actor, tenant: changeset.tenant]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
