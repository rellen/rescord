defmodule Rescord.ReleaseTest do
  @moduledoc """
  Holds the tasks of a release (ADR 0044) that a test can run in its
  transaction: the first root user, one time. `migrate/0` runs in the
  image and the package, against a database of its own.

  `move_storage/2` copies the files of one store into the other, and
  prints the report (ADR 0059). `Rescord.Storage.MoveTest` holds the move
  itself.
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureIO

  alias Rescord.{Accounts, Release}

  test "makes the first root user, and no second one" do
    output = capture_io(fn -> assert :ok = Release.bootstrap_root("first@example.org") end)
    assert output =~ "first@example.org is the first root user."

    assert {:ok, [root]} = Accounts.roots(authorize?: false)
    assert to_string(root.email) == "first@example.org"

    output =
      capture_io(fn ->
        assert {:error, :root_exists} = Release.bootstrap_root("second@example.org")
      end)

    assert output =~ "Rescord has a root user already."
  end

  describe "the move of the files" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      Rescord.StorageFixtures.disk_store!(tmp_dir)
      %{s3: Rescord.StorageFixtures.s3_store!()}
    end

    test "copies from the directory into the bucket and back, and says so",
         %{tmp_dir: tmp_dir, s3: s3} do
      :ok = Rescord.Storage.Disk.put("org-1/photos/a", "a photo", "image/jpeg")
      :ok = Rescord.Storage.Disk.put("org-1/attachments/b", "a report", "application/pdf")

      output = capture_io(fn -> assert :ok = Release.move_storage("disk", "s3") end)

      assert output =~
               "The directory #{tmp_dir} has 2 files, and the bucket rescord at http://s3.test:3900 has 0."

      assert output =~ "copied  2 files"
      assert output =~ "Nothing was deleted"
      assert map_size(Rescord.FakeS3.objects(s3)) == 2

      # The bucket gets a file that the directory does not have, and gives it back.
      :ok = Rescord.Storage.S3.put("org-1/photos/c", "a new photo", "image/jpeg")
      output = capture_io(fn -> assert :ok = Release.move_storage("s3", "disk") end)

      assert output =~ "copied  1 file "
      assert output =~ "same    2 files"
      assert Rescord.Storage.Disk.get("org-1/photos/c") == {:ok, "a new photo"}
    end

    test "returns an error when a file is not copied", %{s3: s3} do
      :ok = Rescord.Storage.Disk.put("org-1/photos/a", "a photo", "image/jpeg")
      Rescord.FakeS3.fault(s3, "org-1/photos/a", {:put, 403})

      output = capture_io(fn -> assert :error = Release.move_storage("disk", "s3") end)

      assert output =~ "FAIL    1 file"
      assert output =~ "org-1/photos/a: the new store did not take it: the service answered 403"
    end

    test "returns an error when a store cannot list its files", %{s3: s3} do
      Rescord.FakeS3.fault(s3, :list, 403)

      output = capture_io(fn -> assert :error = Release.move_storage("disk", "s3") end)

      assert output =~ "Rescord cannot list the files of the bucket rescord"
      assert output =~ "Nothing was copied."
    end

    test "refuses two stores that are the same, and a store that it does not know" do
      for {from, to} <- [{"disk", "disk"}, {"s3", "s3"}, {"disk", "tape"}, {"", "s3"}] do
        output = capture_io(fn -> assert :error = Release.move_storage(from, to) end)
        assert output =~ "disk s3, or s3 disk"
      end
    end
  end
end
