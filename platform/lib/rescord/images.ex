defmodule Rescord.Images do
  @moduledoc """
  Makes a photo safe to keep, and its thumbnail, with libvips through the
  package `image` (ADR 0055).

  `prepare/1` takes the bytes that a person sent, and returns the bytes that
  Rescord keeps:

    * The type comes from the first bytes (`type_of/1`): JPEG, PNG, GIF or
      WebP. libvips reads only those, and `block_untrusted/0` blocks each
      loader that libvips does not trust, at the start of the application.
      A HEIC or an AVIF photo gets words of its own (`heif?/1`).
    * A photo of more than `max_pixels/0` pixels is refused before libvips
      decodes it, so a small file cannot fill the memory.
    * The photo turns as its EXIF orientation says, and then loses all of
      its metadata: EXIF with the GPS position, XMP, IPTC and the comments.
      Rescord writes the photo again, so no metadata and no data after the
      end of the image stays.
    * A photo longer than `max_side/0` pixels on a side becomes that long,
      and a thumbnail of `thumbnail_side/0` pixels at most is a WebP image.
    * An animated GIF keeps its frames, and loses its metadata. Its
      thumbnail is its first frame.

  Only a few photos go through libvips at the same time, each in a process
  of its own (`Rescord.Images.Limit`, ADR 0056). A photo that waits too
  long for its turn is refused with the reason `:busy`, whose words ask the
  person to try again.

  The date that the camera recorded, `DateTimeOriginal` of EXIF, is read
  before the metadata goes, as a suggestion for the date of the photo.
  """

  alias Rescord.Images.Limit
  alias Rescord.Storage.Errors.RefusedFile
  alias Vix.Vips.Image, as: Vimage

  @max_pixels 100_000_000
  @max_side 4096
  @thumbnail_side 480

  @typedoc "What Rescord keeps of a photo."
  @type prepared :: %{
          bytes: binary,
          content_type: String.t(),
          thumbnail: binary,
          taken_at: NaiveDateTime.t() | nil
        }

  @doc "The most pixels of a photo: 100 million."
  def max_pixels, do: @max_pixels

  @doc "The longest side of a photo that Rescord keeps, in pixels."
  def max_side, do: @max_side

  @doc "The longest side of a thumbnail, in pixels."
  def thumbnail_side, do: @thumbnail_side

  @doc """
  Blocks the operations of libvips that its authors do not trust with a
  file from outside, such as the loaders of SVG and of CSV. The application
  calls it at its start.
  """
  @spec block_untrusted() :: :ok | {:error, term}
  def block_untrusted, do: Vix.Vips.block_untrusted_set(true)

  @doc """
  The type of an image from its first bytes, or `nil` for a type that
  Rescord does not take as a photo.

      iex> Rescord.Images.type_of(<<0xFF, 0xD8, 0xFF, 0xE0>>)
      "image/jpeg"

      iex> Rescord.Images.type_of("%PDF-1.7")
      nil
  """
  @spec type_of(binary) :: String.t() | nil
  def type_of(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"
  def type_of(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: "image/png"
  def type_of(<<"GIF87a", _rest::binary>>), do: "image/gif"
  def type_of(<<"GIF89a", _rest::binary>>), do: "image/gif"
  def type_of(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: "image/webp"
  def type_of(_other), do: nil

  # The brands of the box `ftyp` of a HEIF file: the HEIC of a phone, HEIF,
  # and AVIF.
  @heif_brands ~w(heic heix hevc hevx heim heis mif1 msf1 avif avis)

  @doc """
  Whether the first bytes are those of a HEIF file: a HEIC photo of a
  phone, or an AVIF image. Rescord reads neither: the libvips of the
  precompiled NIF of vix has no HEVC decoder. So `prepare/1` refuses such a
  photo with the reason `:heic`, whose words say what to do (issue 34).

      iex> Rescord.Images.heif?(<<0, 0, 0, 24, "ftypheic", 0, 0, 0, 0>>)
      true

      iex> Rescord.Images.heif?(<<0, 0, 0, 24, "ftypisom", 0, 0, 0, 0>>)
      false
  """
  @spec heif?(binary) :: boolean
  def heif?(<<_size::binary-size(4), "ftyp", brand::binary-size(4), _rest::binary>>),
    do: brand in @heif_brands

  def heif?(_other), do: false

  @doc """
  The photo that Rescord keeps, with its thumbnail, or a `RefusedFile`
  error with the reason that it cannot keep it.
  """
  @spec prepare(binary) :: {:ok, prepared} | {:error, RefusedFile.t()}
  def prepare(bytes) when is_binary(bytes) do
    case type_of(bytes) do
      nil -> refused(if heif?(bytes), do: :heic, else: :not_a_photo)
      type -> one_of_few(fn -> prepare(bytes, type) end)
    end
  end

  # libvips takes about 150 MB for a photo of a phone while it works, so
  # only a few photos go through it at once (ADR 0056).
  defp one_of_few(work) do
    case Limit.run(work) do
      {:error, :busy} -> refused(:busy)
      result -> result
    end
  end

  defp prepare(bytes, type) do
    with {:ok, image} <- open(bytes, type),
         :ok <- within_limit(image),
         {:ok, full} <- full(image, type),
         {:ok, thumbnail} <- thumbnail(bytes, image, type) do
      {:ok, %{bytes: full, content_type: type, thumbnail: thumbnail, taken_at: taken_at(image)}}
    else
      {:error, %RefusedFile{} = error} -> {:error, error}
      {:error, _reason} -> refused(:unreadable)
    end
  end

  defp refused(reason), do: {:error, RefusedFile.exception(reason: reason)}

  # libvips reads the header first, and the pixels only when an operation
  # needs them. An animated GIF opens with each of its frames.
  defp open(bytes, "image/gif"), do: Image.from_binary(bytes, pages: :all, fail_on: :error)
  defp open(bytes, _type), do: Image.from_binary(bytes, fail_on: :error)

  defp within_limit(image) do
    if Image.width(image) * Image.height(image) > @max_pixels,
      do: refused(:too_many_pixels),
      else: :ok
  end

  defp full(image, "image/gif") do
    Image.write(image, :memory, suffix: ".gif", strip_metadata: true)
  end

  defp full(image, type) do
    with {:ok, {turned, _how}} <- Image.autorotate(image),
         {:ok, sized} <- Image.thumbnail(turned, @max_side, resize: :down) do
      Image.write(sized, :memory, [suffix: suffix(type), strip_metadata: true] ++ quality(type))
    end
  end

  defp thumbnail(bytes, _image, "image/gif") do
    with {:ok, first} <- Image.from_binary(bytes, fail_on: :error),
         {:ok, small} <- Image.thumbnail(first, @thumbnail_side, resize: :down) do
      Image.write(small, :memory, suffix: ".webp", strip_metadata: true, quality: 80)
    end
  end

  defp thumbnail(_bytes, image, _type) do
    with {:ok, {turned, _how}} <- Image.autorotate(image),
         {:ok, small} <- Image.thumbnail(turned, @thumbnail_side, resize: :down) do
      Image.write(small, :memory, suffix: ".webp", strip_metadata: true, quality: 80)
    end
  end

  defp suffix("image/jpeg"), do: ".jpg"
  defp suffix("image/png"), do: ".png"
  defp suffix("image/webp"), do: ".webp"

  defp quality("image/png"), do: []
  defp quality(_lossy), do: [quality: 90]

  # The date and the time that the camera recorded, with no zone: EXIF has
  # none. A photo with no such date, or with one that is not a date, has nil.
  defp taken_at(%Vimage{} = image) do
    case Image.exif(image) do
      {:ok, exif} ->
        case get_in(exif, [:exif, :datetime_original]) || exif[:datetime_original] do
          %NaiveDateTime{} = at -> at
          _other -> nil
        end

      {:error, _reason} ->
        nil
    end
  rescue
    # A broken EXIF block is no reason to refuse the photo.
    _error -> nil
  end
end
