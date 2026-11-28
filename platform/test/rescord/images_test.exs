defmodule Rescord.ImagesTest do
  @moduledoc """
  Holds what Rescord keeps of a photo (ADR 0055): the type of its first
  bytes, no metadata and no GPS position, the turn that EXIF asks for, the
  size of the photo and of its thumbnail, the frames of a GIF, the date of
  the camera, and the limits.
  """

  use ExUnit.Case, async: true

  import Rescord.StorageFixtures

  alias Rescord.Images
  alias Rescord.Storage.Errors.RefusedFile

  doctest Images

  defp shape(bytes) do
    {:ok, image} = Image.from_binary(bytes)
    {Image.width(image), Image.height(image)}
  end

  test "a photo loses its EXIF block, and the GPS position with it" do
    source = photo(gps: true, taken_at: "2026:10:03 14:22:01")
    assert :binary.match(source, "Exif") != :nomatch
    {:ok, original} = Image.from_binary(source)
    assert {:ok, %{gps: %{gps_latitude: [27, 28, 0]}}} = Image.exif(original)

    assert {:ok, kept} = Images.prepare(source)

    assert kept.content_type == "image/jpeg"
    assert Images.type_of(kept.bytes) == "image/jpeg"
    assert :binary.match(kept.bytes, "Exif") == :nomatch
    assert :binary.match(kept.thumbnail, "Exif") == :nomatch
    {:ok, image} = Image.from_binary(kept.bytes)
    assert {:error, _no_exif} = Image.exif(image)
  end

  test "the date of the camera comes back as a suggestion, and nil when there is none" do
    assert {:ok, %{taken_at: ~N[2026-10-03 14:22:01]}} =
             Images.prepare(photo(taken_at: "2026:10:03 14:22:01"))

    assert {:ok, %{taken_at: nil}} = Images.prepare(photo())
  end

  test "a photo that the camera held on its side turns as its EXIF says" do
    assert {:ok, kept} = Images.prepare(photo(width: 64, height: 32, orientation: 6))
    assert shape(kept.bytes) == {32, 64}
    assert shape(kept.thumbnail) == {32, 64}
  end

  test "a large photo becomes 4096 pixels long, and its thumbnail 480, as a WebP image" do
    assert {:ok, kept} = Images.prepare(photo(width: 5000, height: 50))
    assert shape(kept.bytes) == {Images.max_side(), 41}
    assert shape(kept.thumbnail) == {Images.thumbnail_side(), 5}
    assert Images.type_of(kept.thumbnail) == "image/webp"

    # A small photo keeps its size.
    assert {:ok, small} = Images.prepare(photo(width: 64, height: 32))
    assert shape(small.bytes) == {64, 32}
    assert shape(small.thumbnail) == {64, 32}
  end

  test "a PNG, a WebP image and a GIF keep their types" do
    for {format, type} <- [{".png", "image/png"}, {".webp", "image/webp"}, {".gif", "image/gif"}] do
      assert {:ok, kept} = Images.prepare(photo(format: format))
      assert kept.content_type == type
      assert Images.type_of(kept.bytes) == type
      assert Images.type_of(kept.thumbnail) == "image/webp"
    end
  end

  test "an animated GIF keeps each of its frames, and its thumbnail is the first" do
    {:ok, red} = Vix.Vips.Image.build_image(10, 10, [255, 0, 0])
    {:ok, blue} = Vix.Vips.Image.build_image(10, 10, [0, 0, 255])
    {:ok, frames} = Vix.Vips.Operation.arrayjoin([red, blue], across: 1)

    {:ok, frames} =
      Vix.Vips.Image.mutate(frames, fn mutable ->
        Vix.Vips.MutableImage.set(mutable, "page-height", :gint, 10)
      end)

    {:ok, gif} = Vix.Vips.Image.write_to_buffer(frames, ".gif")

    assert {:ok, kept} = Images.prepare(gif)
    {:ok, again} = Image.from_binary(kept.bytes, pages: :all)
    assert Vix.Vips.Image.header_value(again, "n-pages") == {:ok, 2}
    assert shape(kept.thumbnail) == {10, 10}
  end

  test "refuses a file that is not a photo, and a photo that libvips cannot read" do
    assert {:error, %RefusedFile{reason: :not_a_photo} = error} = Images.prepare("%PDF-1.7 ...")
    assert Exception.message(error) == "is not a photo: Rescord takes JPEG, PNG, GIF and WebP"

    assert {:error, %RefusedFile{reason: :not_a_photo}} =
             Images.prepare("<svg xmlns='http://www.w3.org/2000/svg'/>")

    assert {:error, %RefusedFile{reason: :unreadable} = error} =
             Images.prepare(<<0xFF, 0xD8, 0xFF, 0xE0>> <> String.duplicate("a", 100))

    assert Exception.message(error) == "is a photo that Rescord cannot read"
  end

  test "a photo gets a display file of 1600 pixels at most, as WebP with no metadata (issue 34)" do
    assert {:ok, kept} = Images.prepare(photo(width: 3200, height: 1600, gps: true))
    assert Images.type_of(kept.display) == "image/webp"
    assert shape(kept.display) == {Images.display_side(), 800}
    refute :binary.match(kept.display, "Exif") != :nomatch

    # A small photo keeps its size in its display file.
    assert {:ok, small} = Images.prepare(photo(width: 64, height: 32))
    assert shape(small.display) == {64, 32}

    # A photo turned by its EXIF is turned in its display file too.
    assert {:ok, turned} = Images.prepare(photo(width: 64, height: 32, orientation: 6))
    assert shape(turned.display) == {32, 64}
  end

  test "a GIF has no display file" do
    assert {:ok, %{display: nil}} = Images.prepare(photo(format: ".gif"))
    assert {:ok, nil} = Images.display(photo(format: ".gif"))
  end

  test "display/1 makes the display file of a photo that Rescord keeps already" do
    {:ok, kept} = Images.prepare(photo(width: 2000, height: 1000))
    assert {:ok, display} = Images.display(kept.bytes)
    assert shape(display) == {Images.display_side(), 800}
    assert {:error, %RefusedFile{reason: :not_a_photo}} = Images.display("%PDF-1.7")
  end

  test "refuses a HEIC or an AVIF photo with words that say what to do (issue 34)" do
    for brand <- ~w(heic heix mif1 avif) do
      bytes = <<0, 0, 0, 24, "ftyp", brand::binary, 0, 0, 0, 0, "mif1heic">>
      assert {:error, %RefusedFile{reason: :heic} = error} = Images.prepare(bytes)
      assert Exception.message(error) =~ "HEIC or AVIF photo"
      assert Exception.message(error) =~ "JPEG"
    end

    # An MP4 has a box `ftyp` too, with another brand.
    assert {:error, %RefusedFile{reason: :not_a_photo}} =
             Images.prepare(<<0, 0, 0, 24, "ftypisom", 0, 0, 0, 0>>)
  end

  test "refuses a photo of more than 100 million pixels before it decodes it" do
    # A PNG whose header says 20000 by 20000 pixels, with almost no data:
    # libvips reads the header, and decodes nothing.
    header = <<20_000::32, 20_000::32, 8, 2, 0, 0, 0>>
    data = chunk("IDAT", :zlib.compress(<<0, 0, 0, 0>>))

    png =
      <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <>
        chunk("IHDR", header) <> data <> chunk("IEND", "")

    assert {:error, %RefusedFile{reason: :too_many_pixels} = error} = Images.prepare(png)
    assert Exception.message(error) == "has more than 100 million pixels"
  end

  defp chunk(type, data) do
    <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
  end
end
