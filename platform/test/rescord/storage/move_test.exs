defmodule Rescord.Storage.MoveTest do
  @moduledoc """
  Holds the move of the files from one store into the other (ADR 0059),
  in both directions: from a directory into a bucket of S3, and back. The
  bucket is `Rescord.FakeS3`, in the memory of the test, which gets each
  request that `Rescord.Storage.S3` builds and signs.

  A run copies each file and reads it back, copies only what is missing,
  deletes nothing, writes over nothing, and names each fault.

  The tests change the configuration of the stores, so they do not run
  beside others.
  """

  use ExUnit.Case, async: false

  alias Rescord.{FakeS3, Storage, StorageFixtures}
  alias Rescord.Storage.{Disk, Move, S3}

  @moduletag :tmp_dir

  # The files of two organisations: a photo and its thumbnail, a PDF, a
  # file of a transfer, an empty file, and a file with each byte value.
  defp files do
    %{
      Storage.key("org-1", ["photos", "p1"]) => StorageFixtures.jpeg(),
      Storage.key("org-1", ["thumbnails", "p1"]) =>
        StorageFixtures.photo(format: ".webp", width: 8, height: 8),
      Storage.key("org-1", ["attachments", "a1"]) => StorageFixtures.pdf(),
      Storage.key("org-2", ["transfers", "t1", "f1"]) => "the bytes of a file of a transfer",
      Storage.key("org-2", ["attachments", "empty"]) => "",
      Storage.key("org-2", ["attachments", "bytes"]) => :binary.list_to_bin(Enum.to_list(0..255))
    }
  end

  defp put_all!(store, files) do
    for {key, bytes} <- files, do: :ok = store.put(key, bytes, "application/octet-stream")
    :ok
  end

  defp read_all(store, keys), do: Map.new(keys, &{&1, store.get(&1)})

  defp found(files), do: Map.new(files, fn {key, bytes} -> {key, {:ok, bytes}} end)

  setup %{tmp_dir: tmp_dir} do
    StorageFixtures.disk_store!(tmp_dir)
    %{s3: StorageFixtures.s3_store!()}
  end

  describe "from a directory into a bucket" do
    test "copies each file with the type of its first bytes, and the directory keeps each one",
         %{s3: s3} do
      files = files()
      put_all!(Disk, files)

      assert {:ok, report} = Move.run(Disk, S3)

      assert %Move{files: 6, there: 0, copied: 6, same: 0, left: [], failed: []} = report
      assert report.bytes == files |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum()
      assert Move.complete?(report)

      objects = FakeS3.objects(s3)
      assert Map.new(objects, fn {key, {bytes, _type}} -> {key, bytes} end) == files
      assert {_bytes, "image/jpeg"} = objects["org-1/photos/p1"]
      assert {_bytes, "image/webp"} = objects["org-1/thumbnails/p1"]
      assert {_bytes, "application/pdf"} = objects["org-1/attachments/a1"]
      assert {_bytes, "application/octet-stream"} = objects["org-2/transfers/t1/f1"]

      # Each file was read back from the bucket after its put.
      assert Enum.sort(FakeS3.requests(s3, "PUT")) ==
               files |> Map.keys() |> Enum.map(&"/rescord/#{&1}") |> Enum.sort()

      for path <- FakeS3.requests(s3, "PUT"), do: assert(path in FakeS3.requests(s3, "GET"))

      assert read_all(Disk, Map.keys(files)) == found(files)
      assert FakeS3.requests(s3, "DELETE") == []
    end

    test "a second run copies nothing, and compares each file", %{s3: s3} do
      files = files()
      put_all!(Disk, files)
      assert {:ok, %Move{copied: 6}} = Move.run(Disk, S3)
      puts = FakeS3.requests(s3, "PUT")

      assert {:ok, report} = Move.run(Disk, S3)

      assert %Move{files: 6, there: 6, copied: 0, bytes: 0, same: 6, failed: []} = report
      assert FakeS3.requests(s3, "PUT") == puts
    end

    test "a run after one that stopped copies only what is missing", %{s3: s3} do
      files = files()
      put_all!(Disk, files)

      assert_raise RuntimeError, "the run stops", fn ->
        Move.run(Disk, S3,
          concurrency: 1,
          progress: fn report -> if Move.done(report) == 3, do: raise("the run stops") end
        )
      end

      before = map_size(FakeS3.objects(s3))
      assert before in 3..4

      assert {:ok, report} = Move.run(Disk, S3)

      assert %Move{files: 6, there: ^before, same: ^before, failed: []} = report
      assert report.copied == 6 - before
      assert Map.new(FakeS3.objects(s3), fn {key, {bytes, _type}} -> {key, bytes} end) == files
    end

    test "a file that the bucket refuses is in the report, and the next run copies it",
         %{s3: s3} do
      files = files()
      put_all!(Disk, files)
      FakeS3.fault(s3, "org-1/attachments/a1", {:put, 503})

      assert {:ok, report} = Move.run(Disk, S3)

      assert %Move{copied: 5, failed: [{"org-1/attachments/a1", :put, {:status, 503}}]} = report
      refute Move.complete?(report)
      refute Map.has_key?(FakeS3.objects(s3), "org-1/attachments/a1")

      FakeS3.clear_faults(s3)
      assert {:ok, %Move{copied: 1, same: 5, failed: []}} = Move.run(Disk, S3)
    end

    test "a file that the bucket gives back with other bytes is a fault", %{s3: s3} do
      files = files()
      put_all!(Disk, files)
      FakeS3.fault(s3, "org-1/photos/p1", :corrupt)

      assert {:ok, report} = Move.run(Disk, S3)
      assert %Move{copied: 5, failed: [{"org-1/photos/p1", :check, :differs}]} = report

      # The next run does not take the wrong file for the right one, and
      # does not write over it.
      FakeS3.clear_faults(s3)
      wrong = FakeS3.objects(s3)["org-1/photos/p1"]
      assert {:ok, report} = Move.run(Disk, S3)
      assert %Move{same: 5, failed: [{"org-1/photos/p1", :compare, :differs}]} = report
      assert FakeS3.objects(s3)["org-1/photos/p1"] == wrong
    end

    test "a file that the directory does not give is a fault, and the others are copied",
         %{tmp_dir: tmp_dir} do
      files = files()
      put_all!(Disk, files)
      # A link to a directory, where a file must be.
      File.mkdir_p!(Path.join(tmp_dir, "org-3/photos"))
      File.ln_s!(tmp_dir, Path.join(tmp_dir, "org-3/photos/p9"))

      assert {:ok, report} = Move.run(Disk, S3)
      assert %Move{files: 7, copied: 6, failed: [{"org-3/photos/p9", :read, :eisdir}]} = report
    end

    test "a name that is no key stays, and the report names it", %{tmp_dir: tmp_dir, s3: s3} do
      put_all!(Disk, files())
      File.mkdir_p!(Path.join(tmp_dir, "lost+found"))
      File.write!(Path.join(tmp_dir, "lost+found/inode"), "not of Rescord")
      File.write!(Path.join(tmp_dir, "probe.txt"), "a file with no organisation")
      File.write!(Path.join(tmp_dir, "org-1/photos/p2.part-0a1b2c3d"), "half of a put")

      assert {:ok, report} = Move.run(Disk, S3)

      assert %Move{files: 6, copied: 6, failed: []} = report
      assert report.left == ["lost+found", "org-1/photos/p2.part-0a1b2c3d", "probe.txt"]
      assert map_size(FakeS3.objects(s3)) == 6
    end
  end

  describe "from a bucket into a directory" do
    test "copies each file of each page of the list, and the bucket keeps each one",
         %{tmp_dir: tmp_dir, s3: s3} do
      files = files()
      put_all!(S3, files)
      puts = FakeS3.requests(s3, "PUT")

      assert {:ok, report} = Move.run(S3, Disk)

      assert %Move{files: 6, there: 0, copied: 6, same: 0, left: [], failed: []} = report
      assert read_all(Disk, Map.keys(files)) == found(files)
      for {key, bytes} <- files, do: assert(File.read!(Path.join(tmp_dir, key)) == bytes)

      # The directory has each file under its key, and no part of a put.
      assert Disk.list() == {:ok, files |> Map.keys() |> Enum.sort()}

      assert read_all(S3, Map.keys(files)) == found(files)
      assert FakeS3.requests(s3, "PUT") == puts
      assert FakeS3.requests(s3, "DELETE") == []
    end

    test "a second run copies nothing" do
      put_all!(S3, files())
      assert {:ok, %Move{copied: 6}} = Move.run(S3, Disk)

      assert {:ok, %Move{files: 6, there: 6, copied: 0, same: 6, failed: []}} =
               Move.run(S3, Disk)
    end

    test "a run after one that stopped copies only what is missing" do
      files = files()
      put_all!(S3, files)
      {some, _rest} = files |> Enum.sort() |> Enum.split(2)
      put_all!(Disk, some)

      assert {:ok, %Move{there: 2, copied: 4, same: 2, failed: []}} = Move.run(S3, Disk)
      assert read_all(Disk, Map.keys(files)) == found(files)
    end

    test "a file with other bytes in the directory is a fault, and stays as it is",
         %{tmp_dir: tmp_dir} do
      files = files()
      put_all!(S3, files)
      File.mkdir_p!(Path.join(tmp_dir, "org-1/photos"))
      File.write!(Path.join(tmp_dir, "org-1/photos/p1"), "other bytes")
      # A file that only the directory has.
      :ok = Disk.put("org-9/photos/only-here", "kept", "image/jpeg")

      assert {:ok, report} = Move.run(S3, Disk)

      assert %Move{copied: 5, failed: [{"org-1/photos/p1", :compare, :differs}]} = report
      assert File.read!(Path.join(tmp_dir, "org-1/photos/p1")) == "other bytes"
      assert Disk.get("org-9/photos/only-here") == {:ok, "kept"}
      assert S3.get("org-1/photos/p1") == {:ok, files["org-1/photos/p1"]}
    end

    test "a file that the bucket does not give is a fault, and the others are copied",
         %{s3: s3} do
      put_all!(S3, files())
      FakeS3.fault(s3, "org-2/attachments/bytes", {:get, 500})

      assert {:ok, report} = Move.run(S3, Disk)

      assert %Move{copied: 5, failed: [{"org-2/attachments/bytes", :read, {:status, 500}}]} =
               report

      assert Disk.get("org-2/attachments/bytes") == {:error, :not_found}
    end

    test "a name of the bucket that is no key stays there", %{s3: s3} do
      put_all!(S3, files())
      FakeS3.put_object(s3, "notes & <more>.txt", "not of Rescord")
      FakeS3.put_object(s3, "../outside", "not of Rescord")

      assert {:ok, report} = Move.run(S3, Disk)

      assert %Move{files: 6, copied: 6, failed: []} = report
      assert report.left == ["../outside", "notes & <more>.txt"]
    end
  end

  describe "a store that cannot list its files" do
    test "stops the run before the first copy", %{tmp_dir: tmp_dir, s3: s3} do
      put_all!(Disk, files())
      FakeS3.fault(s3, :list, 403)

      assert Move.run(Disk, S3) == {:error, {:list, :to, {:status, 403}}}
      assert Move.run(S3, Disk) == {:error, {:list, :from, {:status, 403}}}
      assert FakeS3.requests(s3, "PUT") == []

      FakeS3.clear_faults(s3)
      missing = Path.join(tmp_dir, "no-such-directory")
      StorageFixtures.disk_store!(missing)

      assert Move.run(Disk, S3) == {:error, {:list, :from, {:enoent, missing}}}
      assert Move.run(S3, Disk) == {:error, {:list, :to, {:enoent, missing}}}
      assert FakeS3.requests(s3, "PUT") == []
    end
  end

  describe "the words of a run" do
    test "say the files of each store, and each 100 files" do
      report = %Move{files: 250, there: 3}
      line = Move.progress_line(report, Disk, S3)
      assert line =~ ~r/^The directory .+ has 250 files, and the bucket rescord at .+ has 3\.$/

      assert Move.progress_line(%{report | copied: 99}, Disk, S3) == nil
      assert Move.progress_line(%{report | copied: 97, same: 3}, Disk, S3) == "  100 of 250"
      assert Move.progress_line(%{report | copied: 250}, Disk, S3) == nil
    end

    test "say what was copied, and that nothing was deleted", %{tmp_dir: tmp_dir} do
      report = %Move{files: 4, copied: 3, bytes: 2_500_000, same: 1, left: ["lost+found"]}
      words = Move.format(report, Disk, S3)

      assert words =~ "copied  3 files (2.5 MB), and read each one back"
      assert words =~ "same    1 file that the bucket rescord at http://s3.test:3900 had already"
      assert words =~ "left    1 that Rescord did not put there, and does not copy: lost+found"
      assert words =~ "Each file of the directory #{tmp_dir} is in the bucket rescord"
      assert words =~ "Nothing was deleted: the directory #{tmp_dir} keeps its files."
      refute words =~ "FAIL"
    end

    test "name each fault, and no secret" do
      report = %Move{
        files: 3,
        failed: [
          {"org-1/photos/a", :put, {:status, 503}},
          {"org-1/photos/b", :compare, :differs},
          {"org-1/photos/c", :read, :eacces}
        ]
      }

      words = Move.format(report, Disk, S3)

      assert words =~ "FAIL    3 files"
      assert words =~ "org-1/photos/a: the new store did not take it: the service answered 503"
      assert words =~ "org-1/photos/b: the new store has other bytes under this key"
      assert words =~ "org-1/photos/c: the store did not give it: permission denied"
      assert words =~ "Not each file of"
      assert words =~ "run the command again"
      refute words =~ "dec0"

      many = for n <- 1..25, do: {"org-1/photos/#{n}", :put, {:status, 500}}
      words = Move.format(%Move{files: 25, failed: many}, Disk, S3)
      assert words =~ "copied  0 files\nFAIL    25 files"
      assert words =~ "  and 5 more"
    end

    test "say which store could not list its files", %{tmp_dir: tmp_dir} do
      assert Move.format_fault({:list, :to, {:status, 403}}, Disk, S3) =~
               "Rescord cannot list the files of the bucket rescord at http://s3.test:3900: " <>
                 "the service answered 403.\nNothing was copied."

      assert Move.format_fault({:list, :from, {:enoent, tmp_dir}}, Disk, S3) =~
               "cannot list the files of the directory #{tmp_dir}: " <>
                 "no such file or directory: #{tmp_dir}."
    end
  end
end
