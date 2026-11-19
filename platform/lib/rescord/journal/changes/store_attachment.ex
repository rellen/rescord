defmodule Rescord.Journal.Changes.StoreAttachment do
  @moduledoc """
  Gives a new attachment its type, its size and its key, and puts its file
  in the store after the write (ADR 0041).

  The type comes from the first bytes of the file (`type_of/1`), and not
  from its name or from what the browser says. The change refuses a file
  of another type, an empty file, and a file of more than `max_size/0`
  bytes. The key is `<organisation id>/attachments/<attachment id>`.

  The file goes into the store in an `after_action` hook, in the
  transaction: a fault of the store returns an error, and the record is
  not written. A record that the database then refuses leaves a file with
  no record, which is no harm: nothing names it.
  """

  use Ash.Resource.Change

  alias Rescord.{Accounts, Storage}

  @max_size 20_000_000

  @doc "The largest file, in bytes: 20 MB."
  def max_size, do: @max_size

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :content) do
      content when is_binary(content) -> shape(changeset, content)
      _none -> changeset
    end
  end

  defp shape(changeset, content) do
    cond do
      content == "" ->
        error(changeset, "is an empty file")

      byte_size(content) > @max_size ->
        error(changeset, "is more than 20 MB")

      type = type_of(content) ->
        # The id is not set when a change runs, and the key names it.
        id = Ash.Changeset.get_attribute(changeset, :id) || Ash.UUID.generate()
        organisation = Accounts.organisation_of(changeset.to_tenant)
        key = Storage.key(organisation.id, ["attachments", id])

        changeset
        |> Ash.Changeset.force_change_attribute(:id, id)
        |> Ash.Changeset.force_change_attribute(:content_type, type)
        |> Ash.Changeset.force_change_attribute(:size, byte_size(content))
        |> Ash.Changeset.force_change_attribute(:key, key)
        |> Ash.Changeset.after_action(fn _changeset, attachment ->
          case Storage.put(key, content, type) do
            :ok ->
              {:ok, attachment}

            {:error, _reason} ->
              {:error,
               Ash.Error.Changes.InvalidArgument.exception(
                 field: :content,
                 message: "did not reach the store. Try again later"
               )}
          end
        end)

      true ->
        error(changeset, "is not a photo or a PDF: Rescord takes JPEG, PNG, GIF, WebP and PDF")
    end
  end

  defp error(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :content, message: message)

  @doc """
  The type of a file from its first bytes, or `nil` for a type that Rescord
  does not take.

      iex> Rescord.Journal.Changes.StoreAttachment.type_of("%PDF-1.7 ...")
      "application/pdf"

      iex> Rescord.Journal.Changes.StoreAttachment.type_of("<html>")
      nil
  """
  @spec type_of(binary) :: String.t() | nil
  def type_of(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"
  def type_of(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: "image/png"
  def type_of(<<"GIF87a", _rest::binary>>), do: "image/gif"
  def type_of(<<"GIF89a", _rest::binary>>), do: "image/gif"
  def type_of(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: "image/webp"
  def type_of(<<"%PDF-", _rest::binary>>), do: "application/pdf"
  def type_of(_other), do: nil
end
