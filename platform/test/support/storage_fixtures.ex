defmodule Rescord.StorageFixtures do
  @moduledoc """
  Files for the tests of the attachments and the photos (ADR 0041 and
  ADR 0055): real images that libvips reads, a small PDF, and a store in
  the temporary directory of a test.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Vix.Vips.{Image, MutableImage}

  @doc "The bytes of a small JPEG with no metadata."
  def jpeg, do: photo()

  @doc """
  The bytes of the JPEG that Rescord keeps of `jpeg/0`: libvips writes the
  same bytes each time for the same photo.
  """
  def stored_jpeg do
    {:ok, %{bytes: bytes}} = Rescord.Images.prepare(jpeg())
    bytes
  end

  @doc "The bytes of a small PDF."
  def pdf, do: "%PDF-1.7\n" <> String.duplicate("b", 100)

  @doc """
  The bytes of a photo that libvips makes, of one colour.

  ## Options

    * `:width` and `:height` - the size in pixels, 64 by 32 at first;
    * `:format` - `".jpg"` at first, or `".png"`, `".webp"` or `".gif"`;
    * `:gps` - `true` for an EXIF block with a GPS position;
    * `:orientation` - the EXIF orientation, for example `6` for a photo
      that the camera held on its side;
    * `:taken_at` - the EXIF `DateTimeOriginal`, as `"2026:10:03 14:22:01"`.
  """
  def photo(opts \\ []) do
    width = Keyword.get(opts, :width, 64)
    height = Keyword.get(opts, :height, 32)
    {:ok, image} = Image.build_image(width, height, [200, 120, 40])

    {:ok, image} =
      Image.mutate(image, fn mutable ->
        if opts[:gps] do
          :ok = MutableImage.set(mutable, "exif-ifd3-GPSLatitude", :gchararray, "27/1 28/1 0/1")
          :ok = MutableImage.set(mutable, "exif-ifd3-GPSLatitudeRef", :gchararray, "S")
          :ok = MutableImage.set(mutable, "exif-ifd0-Make", :gchararray, "Camera")
        end

        if orientation = opts[:orientation] do
          :ok = MutableImage.set(mutable, "orientation", :gint, orientation)
        end

        if taken_at = opts[:taken_at] do
          :ok = MutableImage.set(mutable, "exif-ifd2-DateTimeOriginal", :gchararray, taken_at)
        end

        :ok
      end)

    {:ok, bytes} = Image.write_to_buffer(image, Keyword.get(opts, :format, ".jpg"))
    bytes
  end

  @doc """
  Keeps the files of the test in `tmp_dir`, a directory of ExUnit's tag
  `:tmp_dir`, and puts the store back after the test.
  """
  def disk_store!(tmp_dir) do
    previous = Application.get_env(:rescord, Rescord.Storage.Disk)
    Application.put_env(:rescord, Rescord.Storage.Disk, root: tmp_dir)
    on_exit(fn -> Application.put_env(:rescord, Rescord.Storage.Disk, previous) end)
    :ok
  end
end
