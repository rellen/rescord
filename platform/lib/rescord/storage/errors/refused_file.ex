defmodule Rescord.Storage.Errors.RefusedFile do
  @moduledoc """
  A file that Rescord does not keep, with the reason (ADR 0077, E2).
  `Rescord.Storage.Upload.prepare/1` and `Rescord.Images.prepare/1` return
  it, and a change of a resource puts its own field on it, such as
  `:content`, before it adds it to the changeset.

  The message follows the name of the field, as in "is an empty file", and
  `Rescord.Accounts.error_messages/1` puts the name of the field in front.

  The reasons:

  - `:empty`: the file has no bytes.
  - `:too_large`: the file is larger than `Rescord.Storage.Upload.max_size/0`.
  - `:not_a_photo_or_pdf`: the first bytes are not those of a type that a
    journal or a receipt takes.
  - `:not_a_photo`: the first bytes are not those of a photo.
  - `:busy`: other photos took each place in libvips for too long (ADR 0056).
  - `:unreadable`: the bytes say photo, and libvips cannot read them.
  - `:too_many_pixels`: the photo has more than 100 million pixels.
  """

  use Splode.Error, fields: [:field, :reason], class: :invalid

  @typedoc "Why the file is refused."
  @type reason ::
          :empty
          | :too_large
          | :not_a_photo_or_pdf
          | :not_a_photo
          | :busy
          | :unreadable
          | :too_many_pixels

  @impl true
  def message(%{reason: reason}), do: words(reason)

  defp words(:empty), do: "is an empty file"
  defp words(:too_large), do: "is more than 20 MB"

  defp words(:not_a_photo_or_pdf),
    do: "is not a photo or a PDF: Rescord takes JPEG, PNG, GIF, WebP and PDF"

  defp words(:not_a_photo), do: "is not a photo: Rescord takes JPEG, PNG, GIF and WebP"
  defp words(:busy), do: "waited too long behind other photos. Try again in a minute"
  defp words(:unreadable), do: "is a photo that Rescord cannot read"
  defp words(:too_many_pixels), do: "has more than 100 million pixels"
end
