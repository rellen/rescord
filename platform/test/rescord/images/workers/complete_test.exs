defmodule Rescord.Images.Workers.CompleteTest do
  @moduledoc """
  Holds the job that completes the files of the photos (issue 34): a
  journal photo of Rescord 0.1.0 comes out with no metadata, a thumbnail
  and a display file, with its size on the attachment, on each version of
  its photo record and in the copy of a transfer; a photo with no display
  file gets one; a second run changes nothing; a photo that libvips cannot
  read is left, with a warning; and `bin/check-files` counts the photos
  that still carry their metadata.

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  require Ecto.Query

  alias Ecto.Query
  alias Rescord.{Images, Journal, Photos, Storage, Transfers}
  alias Rescord.Images.Workers.Complete
  alias Rescord.Transfers.{Snapshot, Transfer}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, wattle_admin} = member!(wattle, :administrator, root)
    {_, banksia_admin} = member!(banksia, :administrator, root)
    lists = lists!(wattle, root)
    options = [actor: wattle_admin, tenant: wattle]
    biscuit = resident!(lists, options)

    entry =
      Journal.write_entry!(
        %{resident_id: biscuit.id, kind: :general, note: "Weighed and checked."},
        options
      )

    {:ok, asked} = Transfers.ask_partner(wattle, banksia.short_name, actor: wattle_admin)
    {:ok, _accepted} = Transfers.accept_partner(asked, actor: banksia_admin)

    {:ok,
     wattle: wattle,
     banksia: banksia,
     wattle_admin: wattle_admin,
     options: options,
     biscuit: biscuit,
     entry: entry}
  end

  # The photo with its GPS position, as a phone sends it.
  defp sent, do: photo(gps: true, width: 2400, height: 1200)

  # A journal photo as Rescord 0.1.0 kept it: the bytes that were sent,
  # their size, and no thumbnail. Its photo record names the same.
  defp old_journal_photo!(context) do
    {:ok, attachment} =
      Journal.attach_file(
        %{entry_id: context.entry.id, name: "biscuit.jpg", content: sent()},
        context.options
      )

    {:ok, photo} = Photos.adopt(attachment.id, context.options)
    :ok = Storage.put(attachment.key, sent(), "image/jpeg")
    set = [size: byte_size(sent()), thumbnail_key: nil, display_key: nil]
    update!(context, "journal_attachments", :id, attachment.id, set)
    update!(context, "photos", :attachment_id, attachment.id, set)
    %{attachment: attachment, photo: photo}
  end

  defp update!(context, table, column, id, set) do
    Query.from(row in table, where: field(row, ^column) == type(^id, Ecto.UUID))
    |> Repo.update_all([set: set], prefix: "org_" <> context.wattle.id)
  end

  defp rows(context, table, column, id) do
    Query.from(row in table,
      where: field(row, ^column) == type(^id, Ecto.UUID),
      select: %{size: row.size, thumbnail_key: row.thumbnail_key, display_key: row.display_key}
    )
    |> Repo.all(prefix: "org_" <> context.wattle.id)
  end

  defp run! do
    {:ok, _job} = Oban.insert(Complete.new(%{}))
    Oban.drain_queue(queue: :images, with_recursion: true, with_safety: false)
  end

  defp exif?(bytes), do: :binary.match(bytes, "Exif") != :nomatch

  test "cleans a journal photo of 0.1.0, its photo record and its copy in a transfer", context do
    %{attachment: attachment, photo: photo} = old_journal_photo!(context)

    # The photo record gets a second version, which names the same files.
    {:ok, _photo} = Photos.describe_photo(photo, %{caption: "On the scale"}, context.options)
    assert length(rows(context, "photos", :id, photo.id)) == 2

    {:ok, transfer} =
      Transfers.send_transfer(
        %{
          organisation_id: context.wattle.id,
          partner_id: context.banksia.id,
          resident_id: context.biscuit.id,
          parts: [:photos]
        },
        actor: context.wattle_admin
      )

    Oban.drain_queue(queue: :transfers)
    [{transfer_id, copy_key}] = Transfers.file_copies(context.wattle.id, attachment.id)
    assert transfer_id == transfer.id
    assert {:ok, copied} = Storage.get(copy_key)
    assert exif?(copied)
    assert Complete.uncleaned(context.wattle.id) == 1

    assert %{success: success, failure: 0} = run!()
    assert success >= 3

    assert {:ok, clean} = Storage.get(attachment.key)
    refute exif?(clean)
    assert Images.type_of(clean) == "image/jpeg"
    thumbnail_key = "#{context.wattle.id}/thumbnails/#{attachment.id}"
    display_key = "#{context.wattle.id}/displays/#{attachment.id}"
    assert {:ok, thumbnail} = Storage.get(thumbnail_key)
    assert {:ok, display} = Storage.get(display_key)
    assert Images.type_of(thumbnail) == "image/webp"
    assert Images.type_of(display) == "image/webp"
    {:ok, shown} = Image.from_binary(display)
    assert Image.width(shown) == Images.display_side()

    expected = %{size: byte_size(clean), thumbnail_key: thumbnail_key, display_key: display_key}
    assert rows(context, "journal_attachments", :id, attachment.id) == [expected]
    assert rows(context, "photos", :id, photo.id) == [expected, expected]
    assert Complete.uncleaned(context.wattle.id) == 0

    # The copy holds the clean bytes, and says their size.
    assert {:ok, ^clean} = Storage.get(copy_key)
    copy = Ash.get!(Transfer, transfer.id, authorize?: false).snapshot
    assert [%{"size" => size}] = Enum.filter(Snapshot.files(copy), &(&1["id"] == attachment.id))
    assert size == byte_size(clean)

    # The pages read the new files.
    assert {:ok, _attachment, ^display} =
             Journal.attachment_display(attachment.id, context.options)

    assert {:ok, _photo, ^display} = Photos.photo_file(photo.id, :display, context.options)

    # A second run finds nothing to do.
    assert %{failure: 0} = run!()
    assert {:ok, ^clean} = Storage.get(attachment.key)
    assert rows(context, "journal_attachments", :id, attachment.id) == [expected]
  end

  test "gives a display file to a photo from before the display files", context do
    photo =
      Photos.add_photo!(%{resident_id: context.biscuit.id, content: sent()}, context.options)

    assert is_binary(photo.display_key)
    assert {:ok, display} = Storage.get(photo.display_key)
    update!(context, "photos", :id, photo.id, display_key: nil)
    :ok = Storage.delete(photo.display_key)

    assert %{failure: 0} = run!()

    assert [%{display_key: key}] = rows(context, "photos", :id, photo.id)
    assert key == "#{context.wattle.id}/displays/#{photo.id}"
    assert {:ok, ^display} = Storage.get(key)
  end

  test "a GIF and a PDF get no display file", context do
    for {name, content} <- [{"a.gif", photo(format: ".gif")}, {"a.pdf", pdf()}] do
      {:ok, attachment} =
        Journal.attach_file(
          %{entry_id: context.entry.id, name: name, content: content},
          context.options
        )

      assert attachment.display_key == nil
    end

    assert %{failure: 0} = run!()
    {:ok, files} = Storage.files()
    refute Enum.any?(files, fn {key, _size} -> key =~ "/displays/" end)
  end

  test "leaves a photo that it cannot read, with a warning, and goes on", context do
    %{attachment: broken} = old_journal_photo!(context)
    :ok = Storage.put(broken.key, <<0xFF, 0xD8, 0xFF, 0xE0>> <> "not a photo", "image/jpeg")
    %{attachment: good} = old_journal_photo!(context)

    log = capture_log(fn -> assert %{failure: 0} = run!() end)

    assert log =~ "could not complete"
    assert [%{thumbnail_key: nil}] = rows(context, "journal_attachments", :id, broken.id)
    assert [%{thumbnail_key: key}] = rows(context, "journal_attachments", :id, good.id)
    assert is_binary(key)
    assert Complete.uncleaned(context.wattle.id) == 1

    output = capture_io(fn -> Rescord.Release.check_files() end)
    assert output =~ "Journal photos that still carry their metadata: 1."
  end
end
