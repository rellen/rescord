defmodule Rescord.PhotosTest do
  @moduledoc """
  Holds the photos of the residents (ADR 0055): a photo with its caption
  and date and no metadata, the photos of the journal, the albums, the
  profile picture, what a removal ends, and who does what.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Journal, Photos, Storage}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    {_, other} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    biscuit = resident!(lists, options)
    pepper = resident!(lists, options, %{name: "Pepper"})

    {:ok,
     organisation: organisation,
     administrator: administrator,
     member: member,
     other: other,
     options: options,
     biscuit: biscuit,
     pepper: pepper,
     today: Accounts.today(organisation)}
  end

  defp add(context, extra \\ %{}, options \\ nil) do
    %{resident_id: context.biscuit.id, content: photo(gps: true)}
    |> Map.merge(extra)
    |> Photos.add_photo(options || context.options)
  end

  defp journal_photo(context, content \\ photo()) do
    {:ok, entry} =
      Journal.write_entry_with_files(
        %{resident_id: context.biscuit.id, kind: :general, note: "In the garden."},
        [{"garden.jpg", content}],
        context.options
      )

    {:ok, %{} = by_entry} = Journal.attachments_of([entry.id], context.options)
    [attachment] = by_entry[entry.id]
    {entry, attachment}
  end

  describe "a photo" do
    test "keeps no metadata, has a thumbnail, and keys of the organisation", context do
      assert {:ok, photo} = add(context, %{caption: "  On the sofa  "})

      assert photo.caption == "On the sofa"
      assert photo.content_type == "image/jpeg"
      assert photo.author_id == context.member.id
      assert photo.key == "#{context.organisation.id}/photos/#{photo.id}"
      assert photo.thumbnail_key == "#{context.organisation.id}/thumbnails/#{photo.id}"

      {:ok, bytes} = Storage.get(photo.key)
      assert photo.size == byte_size(bytes)
      assert :binary.match(bytes, "Exif") == :nomatch
      assert {:ok, thumbnail} = Storage.get(photo.thumbnail_key)
      assert Rescord.Images.type_of(thumbnail) == "image/webp"

      assert {:ok, found, ^bytes} = Photos.photo_file(photo.id, :photo, context.options)
      assert found.id == photo.id
      assert {:ok, _found, ^thumbnail} = Photos.photo_file(photo.id, :thumbnail, context.options)
    end

    test "has the date of the person, or of the camera, or of today", context do
      camera = photo(taken_at: "2026:10:03 14:22:01")

      assert {:ok, %{taken_on: ~D[2026-10-03]}} = add(context, %{content: camera})

      assert {:ok, %{taken_on: ~D[2026-09-01]}} =
               add(context, %{content: camera, taken_on: ~D[2026-09-01]})

      assert {:ok, %{taken_on: today}} = add(context, %{content: photo()})
      assert today == context.today

      # A camera with its clock in the future gives today.
      future = context.today |> Date.add(30) |> Calendar.strftime("%Y:%m:%d 10:00:00")
      assert {:ok, %{taken_on: ^today}} = add(context, %{content: photo(taken_at: future)})
    end

    test "refuses a date after today, a file that is not a photo, and an empty file", context do
      for {extra, words} <- [
            {%{taken_on: Date.add(context.today, 1)}, "Taken on cannot be after today"},
            {%{content: pdf()}, "is not a photo"},
            {%{content: ""}, "is an empty file"}
          ] do
        assert {:error, %Ash.Error.Invalid{} = error} = add(context, extra)
        assert hd(Accounts.error_messages(error)) =~ words
      end

      assert {:ok, []} = Photos.photos_of(context.biscuit.id, context.options)
    end

    test "takes no key, type, size, author or attachment as input", context do
      for extra <- [
            %{key: "x"},
            %{content_type: "text/html"},
            %{size: 1},
            %{author_id: context.other.id},
            %{attachment_id: Ash.UUID.generate()}
          ] do
        assert {:error, %Ash.Error.Invalid{}} = add(context, extra)
      end
    end

    test "changes its caption and its date, and keeps the history", context do
      {:ok, photo} = add(context, %{caption: "Asleep"})
      before = DateTime.utc_now()

      {:ok, changed} =
        Photos.describe_photo(
          photo,
          %{caption: "Awake", taken_on: ~D[2026-01-02]},
          context.options
        )

      assert {changed.caption, changed.taken_on} == {"Awake", ~D[2026-01-02]}

      assert {:ok, %{caption: "Asleep"}} =
               Photos.photo(photo.id, [as_of: before] ++ context.options)
    end
  end

  describe "the photos of a resident" do
    test "hold the photos of its journal, with the date of their entry, and no copy", context do
      {entry, attachment} = journal_photo(context, photo(gps: true))
      {:ok, own} = add(context, %{taken_on: Date.add(context.today, -1)})

      # A photo of the journal loses its metadata too, and has a thumbnail.
      {:ok, bytes} = Storage.get(attachment.key)
      assert :binary.match(bytes, "Exif") == :nomatch
      assert is_binary(attachment.thumbnail_key)

      assert {:ok, [first, second]} = Photos.photos_of(context.biscuit.id, context.options)
      assert first.photo == nil
      assert first.attachment.id == attachment.id
      assert first.entry_id == entry.id
      assert first.taken_on == Accounts.local_date(context.organisation, entry.happened_at)
      assert second.photo.id == own.id

      # Pepper has none of them.
      assert {:ok, []} = Photos.photos_of(context.pepper.id, context.options)

      # A PDF of the journal is not a photo.
      {:ok, pdf_entry} =
        Journal.write_entry_with_files(
          %{resident_id: context.biscuit.id, kind: :general, note: "The report."},
          [{"report.pdf", pdf()}],
          context.options
        )

      assert {:ok, items} = Photos.photos_of(context.biscuit.id, context.options)
      refute Enum.any?(items, &(&1.entry_id == pdf_entry.id))
    end

    test "a photo of the journal becomes a record once, with the same files", context do
      {entry, attachment} = journal_photo(context)
      {:ok, [item]} = Photos.photos_of(context.biscuit.id, context.options)

      assert {:ok, photo} =
               Photos.keep(
                 item,
                 %{caption: "In the sun", taken_on: nil, album_ids: []},
                 context.options
               )

      assert photo.attachment_id == attachment.id
      assert photo.key == attachment.key
      assert photo.thumbnail_key == attachment.thumbnail_key
      assert photo.resident_id == context.biscuit.id
      assert photo.taken_on == Accounts.local_date(context.organisation, entry.happened_at)

      assert {:ok, [kept]} = Photos.photos_of(context.biscuit.id, context.options)
      assert kept.photo.id == photo.id
      assert kept.caption == "In the sun"
      assert kept.entry_id == entry.id

      # A second adoption finds the same record.
      assert {:ok, %{id: same}} = Photos.adopt(attachment.id, context.options)
      assert same == photo.id
    end

    test "a photo of the journal leaves the photos with its attachment", context do
      {_entry, attachment} = journal_photo(context)
      {:ok, photo} = Photos.adopt(attachment.id, context.options)
      {:ok, _profile} = Photos.set_profile_photo(photo, context.options)

      :ok = Journal.remove_attachment(attachment, context.options)

      assert {:ok, []} = Photos.photos_of(context.biscuit.id, context.options)
      assert {:ok, nil} = Photos.profile_photo(context.biscuit.id, context.options)
      assert {:error, :not_found} = Photos.photo_file(photo.id, :photo, context.options)
    end

    test "adopt refuses a PDF of the journal", context do
      {:ok, entry} =
        Journal.write_entry_with_files(
          %{resident_id: context.biscuit.id, kind: :general, note: "The report."},
          [{"report.pdf", pdf()}],
          context.options
        )

      {:ok, %{} = by_entry} = Journal.attachments_of([entry.id], context.options)
      [report] = by_entry[entry.id]

      assert {:error, %Ash.Error.Invalid{} = error} = Photos.adopt(report.id, context.options)
      assert Accounts.error_messages(error) == ["Attachment is not a photo of a journal entry"]
    end
  end

  describe "the albums" do
    test "hold a photo in several albums, and keep the photos when they go", context do
      {:ok, photo} = add(context)

      {:ok, surgery} =
        Photos.make_album(%{resident_id: context.biscuit.id, name: "Surgery"}, context.options)

      {:ok, adoption} =
        Photos.make_album(%{resident_id: context.biscuit.id, name: "Adoption"}, context.options)

      {:ok, [item]} = Photos.photos_of(context.biscuit.id, context.options)
      ids = [surgery.id, adoption.id]

      {:ok, _photo} =
        Photos.keep(item, %{caption: nil, taken_on: nil, album_ids: ids}, context.options)

      assert {:ok, [%{album_ids: in_albums} = item]} =
               Photos.photos_of(context.biscuit.id, context.options)

      assert Enum.sort(in_albums) == Enum.sort(ids)

      assert {:ok, [%{name: "Adoption"}, %{name: "Surgery"}]} =
               Photos.albums(context.biscuit.id, context.options)

      {:ok, _photo} =
        Photos.keep(
          item,
          %{caption: nil, taken_on: nil, album_ids: [adoption.id]},
          context.options
        )

      assert {:ok, [%{album_ids: [only]}]} = Photos.photos_of(context.biscuit.id, context.options)
      assert only == adoption.id

      :ok = Photos.remove_album(adoption, context.options)

      assert {:ok, [%{album_ids: []} = left]} =
               Photos.photos_of(context.biscuit.id, context.options)

      assert left.photo.id == photo.id
      assert {:ok, [%{name: "Surgery"}]} = Photos.albums(context.biscuit.id, context.options)
    end

    test "refuse a photo of another resident", context do
      {:ok, photo} = add(context)

      {:ok, album} =
        Photos.make_album(%{resident_id: context.pepper.id, name: "Pepper"}, context.options)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Photos.add_to_album(%{album_id: album.id, photo_id: photo.id}, context.options)

      assert Accounts.error_messages(error) == ["Photo is not a photo of this resident"]
    end
  end

  describe "the profile picture" do
    test "is one photo of the resident at a time, with its history", context do
      {:ok, first} = add(context)
      {:ok, second} = add(context)
      assert {:ok, nil} = Photos.profile_photo(context.biscuit.id, context.options)

      {:ok, _profile} = Photos.set_profile_photo(first, context.options)
      assert {:ok, %{id: id}} = Photos.profile_photo(context.biscuit.id, context.options)
      assert id == first.id
      between = DateTime.utc_now()

      {:ok, _profile} = Photos.set_profile_photo(second, context.options)
      assert {:ok, %{id: id}} = Photos.profile_photo(context.biscuit.id, context.options)
      assert id == second.id

      assert {:ok, %{id: then}} =
               Photos.profile_photo(context.biscuit.id, [as_of: between] ++ context.options)

      assert then == first.id

      assert {:ok, map} =
               Photos.profile_photos([context.biscuit.id, context.pepper.id], context.options)

      assert Map.keys(map) == [context.biscuit.id]

      :ok = Photos.clear_profile_photo(context.biscuit.id, context.options)
      assert {:ok, nil} = Photos.profile_photo(context.biscuit.id, context.options)
    end

    test "ends with the removal of its photo, as its albums do", context do
      {:ok, photo} = add(context)

      {:ok, album} =
        Photos.make_album(%{resident_id: context.biscuit.id, name: "Home"}, context.options)

      {:ok, _tie} =
        Photos.add_to_album(%{album_id: album.id, photo_id: photo.id}, context.options)

      {:ok, _profile} = Photos.set_profile_photo(photo, context.options)

      :ok = Photos.remove_photo(photo, context.options)

      # The ties end, and do not only drop out of sight with their photo.
      read = [tenant: context.organisation, authorize?: false]
      assert Ash.read!(Rescord.Photos.ProfilePhoto, read) == []
      assert Ash.read!(Rescord.Photos.AlbumPhoto, read) == []

      assert {:ok, nil} = Photos.profile_photo(context.biscuit.id, context.options)
      assert {:ok, []} = Photos.photos_of(context.biscuit.id, context.options)
      assert {:ok, nil} = Photos.photo(photo.id, context.options)

      # The same photo can be the picture of another resident never.
      {:ok, other} = add(context, %{resident_id: context.pepper.id})

      assert {:error, %Ash.Error.Invalid{}} =
               Rescord.Photos.ProfilePhoto
               |> Ash.Changeset.for_create(
                 :choose,
                 %{resident_id: context.biscuit.id, photo_id: other.id},
                 context.options
               )
               |> Ash.create()
    end
  end

  describe "the grants" do
    test "a member removes the photos that they added; the power remove_residents removes each one",
         context do
      {:ok, own} = add(context)
      {:ok, theirs} = add(context, %{}, actor: context.other, tenant: context.organisation)

      assert {:error, %Ash.Error.Forbidden{}} = Photos.remove_photo(theirs, context.options)
      assert :ok = Photos.remove_photo(own, context.options)

      assert :ok =
               Photos.remove_photo(theirs,
                 actor: context.administrator,
                 tenant: context.organisation
               )

      role = fn user ->
        {:ok, _organisation, member} =
          Accounts.organisation_for(user, context.organisation.short_name)

        Accounts.role_in(user, member)
      end

      refute Photos.can_remove_photo?(role.(context.member), context.member, theirs)
      assert Photos.can_remove_photo?(role.(context.member), context.member, own)
      assert Photos.can_remove_photo?(role.(context.administrator), context.administrator, theirs)
    end

    test "a person outside the organisation adds and reads no photo", context do
      {:ok, photo} = add(context)
      outsider = [actor: user!(), tenant: context.organisation]

      assert {:error, %Ash.Error.Forbidden{}} = add(context, %{}, outsider)
      assert {:ok, nil} = Photos.photo(photo.id, outsider)
      assert {:error, :not_found} = Photos.photo_file(photo.id, :photo, outsider)
    end
  end
end
