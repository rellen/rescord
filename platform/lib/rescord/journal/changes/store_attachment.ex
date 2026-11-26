defmodule Rescord.Journal.Changes.StoreAttachment do
  @moduledoc """
  Gives a new attachment its type, its size and its key, and puts its file
  in the store after the write (ADR 0041).

  The type comes from the first bytes of the file (`type_of/1`), and not
  from its name or from what the browser says. The change refuses a file
  of another type, an empty file, and a file of more than `max_size/0`
  bytes. The key is `<organisation id>/attachments/<attachment id>`.

  A photo goes through `Rescord.Images.prepare/1` first (ADR 0055): it
  turns as its EXIF says and loses its metadata, the GPS position with the
  rest, and gets a thumbnail at `<organisation id>/thumbnails/<attachment
  id>`. The size is then the size of the photo that Rescord keeps. A PDF
  stays as the person sent it.

  The files go into the store in an `after_action` hook, in the
  transaction: a fault of the store returns an error, and the record is
  not written. A record that the database then refuses leaves a file with
  no record, which is no harm: nothing names it.
  """

  use Ash.Resource.Change

  alias Rescord.{Accounts, Images, Storage}

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
        case prepare(content, type) do
          {:ok, files} -> store(changeset, files)
          {:error, words} -> error(changeset, words)
        end

      true ->
        error(changeset, "is not a photo or a PDF: Rescord takes JPEG, PNG, GIF, WebP and PDF")
    end
  end

  defp prepare(content, "application/pdf"),
    do: {:ok, %{bytes: content, content_type: "application/pdf", thumbnail: nil}}

  defp prepare(content, _image), do: Images.prepare(content)

  defp store(changeset, files) do
    # The id is not set when a change runs, and the keys name it.
    id = Ash.Changeset.get_attribute(changeset, :id) || Ash.UUID.generate()
    organisation = Accounts.organisation_of(changeset.to_tenant)
    key = Storage.key(organisation.id, ["attachments", id])
    thumbnail_key = files.thumbnail && Storage.key(organisation.id, ["thumbnails", id])

    changeset
    |> Ash.Changeset.force_change_attribute(:id, id)
    |> Ash.Changeset.force_change_attribute(:content_type, files.content_type)
    |> Ash.Changeset.force_change_attribute(:size, byte_size(files.bytes))
    |> Ash.Changeset.force_change_attribute(:key, key)
    |> Ash.Changeset.force_change_attribute(:thumbnail_key, thumbnail_key)
    |> Ash.Changeset.after_action(fn _changeset, attachment ->
      with :ok <- Storage.put(key, files.bytes, files.content_type),
           :ok <- put_thumbnail(thumbnail_key, files.thumbnail) do
        {:ok, attachment}
      else
        {:error, _reason} ->
          {:error,
           Ash.Error.Changes.InvalidArgument.exception(
             field: :content,
             message: "did not reach the store. Try again later"
           )}
      end
    end)
  end

  defp put_thumbnail(nil, _bytes), do: :ok
  defp put_thumbnail(key, bytes), do: Storage.put(key, bytes, "image/webp")

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
  def type_of(<<"%PDF-", _rest::binary>>), do: "application/pdf"
  def type_of(bytes), do: Images.type_of(bytes)
end
