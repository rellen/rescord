defmodule Rescord.Storage.Upload do
  @moduledoc """
  What a person sends as a file of a record: a photo or a PDF (ADR 0041).
  The attachments of the journal and the receipts of the expenses share it.

  `prepare/1` reads the type from the first bytes of the file, and not from
  its name or from what the browser says: a JPEG, a PNG, a GIF, a WebP image
  or a PDF. It refuses another type, an empty file, and a file of more than
  `max_size/0` bytes. A photo goes through `Rescord.Images.prepare/1`
  (ADR 0055): it turns as its EXIF says, loses its metadata, the GPS position
  with the rest, and gets a thumbnail. A PDF stays as the person sent it.

  `put/3` puts the file and its thumbnail in the store.
  """

  alias Rescord.{Images, Storage}

  @max_size 20_000_000

  @typedoc "A file that is ready for the store: its bytes, its type, and a thumbnail or none."
  @type files :: %{
          required(:bytes) => binary,
          required(:content_type) => String.t(),
          required(:thumbnail) => binary | nil,
          optional(atom) => term
        }

  @doc "The largest file, in bytes: 20 MB."
  @spec max_size() :: pos_integer
  def max_size, do: @max_size

  @doc """
  The type of a file from its first bytes, or `nil` for a type that Rescord
  does not take.

      iex> Rescord.Storage.Upload.type_of("%PDF-1.7 ...")
      "application/pdf"

      iex> Rescord.Storage.Upload.type_of("<html>")
      nil
  """
  @spec type_of(binary) :: String.t() | nil
  def type_of(<<"%PDF-", _rest::binary>>), do: "application/pdf"
  def type_of(bytes), do: Images.type_of(bytes)

  @doc """
  Makes a file ready for the store, or says in words why Rescord does not
  take it. The words follow the name of the field: "is an empty file".
  """
  @spec prepare(binary) :: {:ok, files} | {:error, String.t()}
  def prepare(""), do: {:error, "is an empty file"}

  def prepare(content) when byte_size(content) > @max_size, do: {:error, "is more than 20 MB"}

  def prepare(content) when is_binary(content) do
    case type_of(content) do
      nil ->
        {:error, "is not a photo or a PDF: Rescord takes JPEG, PNG, GIF, WebP and PDF"}

      "application/pdf" ->
        {:ok, %{bytes: content, content_type: "application/pdf", thumbnail: nil}}

      _image ->
        Images.prepare(content)
    end
  end

  @doc """
  Puts a prepared file under `key`, and its thumbnail under `thumbnail_key`
  when it has one.
  """
  @spec put(Storage.key(), Storage.key() | nil, files) :: :ok | {:error, term}
  def put(key, thumbnail_key, files) do
    with :ok <- Storage.put(key, files.bytes, files.content_type) do
      if thumbnail_key && files.thumbnail,
        do: Storage.put(thumbnail_key, files.thumbnail, "image/webp"),
        else: :ok
    end
  end
end
