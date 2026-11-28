defmodule Rescord.StorageFixtures do
  @moduledoc """
  Files for the tests of the attachments and the photos (ADR 0041 and
  ADR 0055): real images that libvips reads, a small PDF, a store in the
  temporary directory of a test, and a store of S3 in its memory.
  """

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
    Shoddy.Tests.put_app_env(:rescord, Rescord.Storage.Disk, root: tmp_dir)
  end

  @doc """
  Starts a service of S3 in the memory of the test (`Rescord.FakeS3`),
  names it in the settings of `Rescord.Storage.S3`, and puts the settings
  back after the test. It returns the service, for `Rescord.FakeS3`. The
  options go to `Rescord.FakeS3.start_link/1`.
  """
  def s3_store!(opts \\ []) do
    service = ExUnit.Callbacks.start_supervised!({Rescord.FakeS3, opts})

    Shoddy.Tests.put_app_env(:rescord, Rescord.Storage.S3,
      endpoint: "http://s3.test:3900",
      region: "garage",
      bucket: Keyword.get(opts, :bucket, "rescord"),
      access_key_id: "GK0000000000000000000000ad",
      secret_access_key: "000000000000000000000000000000000000000000000000000000000000dec0",
      req_options: [plug: &Rescord.FakeS3.call(&1, service), retry: false]
    )

    service
  end
end
