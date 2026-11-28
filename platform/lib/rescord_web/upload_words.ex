defmodule RescordWeb.UploadWords do
  @moduledoc """
  The words of a file that the browser refuses, which the three forms that
  take photos share: the photos of a resident, the files of a journal
  entry and the receipts of an expense (issue 34).

  A HEIC or an AVIF photo has words of its own, since the words "Rescord
  takes JPEG, PNG, GIF or WebP" do not say what to do with it. The browser
  refuses it with `:not_accepted`, by its name or its type, before a byte
  arrives. The accept list of a form never names `.heic`: an iPhone turns a
  HEIC photo of its library into a JPEG when the page does not take HEIC.
  """

  @heif_extensions ~w(.heic .heif .avif)
  @heif_types ~w(image/heic image/heif image/heic-sequence image/heif-sequence image/avif)

  @doc """
  Whether the browser names an entry of an upload as a HEIC or an AVIF
  photo, by the extension of its name or by its type.

      iex> RescordWeb.UploadWords.heif?(%{client_name: "IMG_0042.HEIC", client_type: ""})
      true

      iex> RescordWeb.UploadWords.heif?(%{client_name: "dog.jpg", client_type: "image/jpeg"})
      false
  """
  @spec heif?(map) :: boolean
  def heif?(%{client_name: name, client_type: type}) do
    String.downcase(Path.extname(name || "")) in @heif_extensions or
      String.downcase(type || "") in @heif_types
  end

  def heif?(_entry), do: false

  @doc "The words of a HEIC or an AVIF photo that the browser refused."
  @spec heif() :: String.t()
  def heif,
    do:
      "Rescord cannot read HEIC or AVIF photos. On an iPhone, pick the photo from Photos, " <>
        "which sends a JPEG, or set Settings, Camera, Formats to Most Compatible. " <>
        "On another device, save the photo as a JPEG first."

  @doc """
  The words of `error` of `entry`: those of a HEIC or AVIF photo for an
  entry that the browser did not accept, and otherwise `words.(error)`, the
  words of the form.
  """
  @spec of(atom, map, (atom -> String.t())) :: String.t()
  def of(:not_accepted, entry, words),
    do: if(heif?(entry), do: heif(), else: words.(:not_accepted))

  def of(error, _entry, words), do: words.(error)
end
