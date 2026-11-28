defmodule Rescord.ReleaseTest do
  @moduledoc """
  Holds the tasks of a release (ADR 0044) that a test can run in its
  transaction: the first root user, one time. `migrate/0` runs in the
  image and the package, against a database of its own.

  `move_storage/2` copies the files of one store into the other, and
  prints the report (ADR 0059). `Rescord.Storage.MoveTest` holds the move
  itself.

  `check_files/1` compares the store with the database, and prints the
  report (ADR 0091). `Rescord.Release.FilesTest` and
  `Rescord.Storage.CompareTest` hold the comparison itself.
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

  describe "the change of the secret of the server" do
    import Rescord.AccountsFixtures
    import Rescord.RubyFixtures

    @old "the secret that the server had before, 32 bytes"
    @new "the secret that the server has now, 32 bytes long"

    test "encrypts each value again, says the counts, and prints no secret" do
      secrets!(@old)
      root = root!()
      provider = provider!(root)
      organisation = organisation!(root)
      keys = Rescord.Transfers.Keys.of(organisation)
      secrets!(@new, @old)

      output = capture_io(fn -> assert :ok = Release.rotate_vault() end)

      assert output =~
               "The secrets of the settings: 1 encrypted again, 0 had the secret of today, 0 open with neither secret."

      assert output =~
               "The keys of the transfers: 1 encrypted again, 0 had the secret of today, 0 open with neither secret."

      assert output =~ "Take RESCORD_KEY_SECRET_PREVIOUS out now"
      for secret <- [@old, @new, key()], do: refute(output =~ secret)

      # The old secret can go.
      secrets!(@new)
      assert {:ok, %{api_key: opened}} = Rescord.Ruby.LLM.profile_of(provider)
      assert opened == key()
      assert Rescord.Transfers.Keys.of(organisation) == keys

      output = capture_io(fn -> assert :ok = Release.rotate_vault() end)
      assert output =~ "The secrets of the settings: 0 encrypted again, 1 had the secret of today"
      assert output =~ "RESCORD_KEY_SECRET_PREVIOUS is not set"
    end

    test "says that a value opens with neither secret, and fails" do
      secrets!(@old)
      provider!(root!())
      secrets!(@new)

      output = capture_io(fn -> assert :error = Release.rotate_vault() end)
      assert output =~ "0 encrypted again, 0 had the secret of today, 1 open with neither secret."
      assert output =~ "Some values open with neither secret"
    end
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

  describe "the comparison of the store with the database" do
    import Rescord.AccountsFixtures
    import Rescord.ResidentsFixtures
    import Rescord.StorageFixtures

    alias Rescord.{FakeS3, Photos, Storage}

    setup do
      s3 = s3_store!()
      Shoddy.Tests.put_app_env(:rescord, :storage, Storage.S3)

      root = root!()
      organisation = organisation!(root, "Wattle Creek")
      {_, administrator} = member!(organisation, :administrator, root)
      options = [actor: administrator, tenant: organisation]
      biscuit = resident!(lists!(organisation, root), options)

      photo =
        Photos.add_photo!(
          %{resident_id: biscuit.id, content: photo(), caption: "Biscuit on the sofa"},
          options
        )

      %{s3: s3, organisation: organisation, photo: photo}
    end

    test "says the leftovers with their size, changes nothing, and is no failure",
         %{s3: s3, organisation: organisation, photo: photo} do
      leftover = Storage.key(organisation.id, ["photos", "0a1b2c3d"])
      FakeS3.put_object(s3, leftover, String.duplicate("p", 2_500))
      before = FakeS3.objects(s3)

      output = capture_io(fn -> assert :ok = Release.check_files() end)

      assert output =~ "The bucket rescord at http://s3.test:3900 has 4 files"
      assert output =~ "and Rescord has 1 organisation."
      assert output =~ "named     3 files"
      assert output =~ "leftover  1 file (2.5 kB) that no record names\n  #{leftover}  2.5 kB\n"
      assert output =~ "Run the command\nagain: a leftover is in both runs."
      assert output =~ "The store has each file that a record names.\nNothing was changed."
      refute output =~ "FAIL"

      # Ids, keys and sizes, and nothing that a person typed.
      refute output =~ "Biscuit"
      refute output =~ photo.id

      assert FakeS3.objects(s3) == before
      assert FakeS3.requests(s3, "PUT") |> length() == 3

      assert FakeS3.requests(s3, "DELETE") == []
    end

    test "fails for a file that a record names and the bucket does not have",
         %{organisation: organisation, photo: photo} do
      :ok = Storage.delete(photo.key)

      output = capture_io(fn -> assert :missing = Release.check_files(all: true) end)

      assert output =~ "FAIL      1 file that a record names, and that the store does not have\n"

      assert output =~
               "  #{photo.key}: photo #{photo.id}, of the organisation #{organisation.id}\n"

      assert output =~ "look for each FAIL in\na backup of the store"
      refute output =~ "leftover"
      refute output =~ "Biscuit"
    end

    test "says so when the bucket does not list its files, and compares nothing", %{s3: s3} do
      FakeS3.fault(s3, :list, 403)

      output = capture_io(fn -> assert :error = Release.check_files() end)

      assert output ==
               "Rescord cannot list the files of the bucket rescord at http://s3.test:3900: " <>
                 "the service answered 403.\nNothing was compared.\n"
    end
  end
end
