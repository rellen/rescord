defmodule RescordWeb.PhotoPagesTest do
  @moduledoc """
  Holds the photos of a resident on the pages (ADR 0055): the page of the
  photos with the photos of the journal, new photos with their caption and
  album, the form of a photo, the albums, the profile picture on the page
  of the resident and in the list of the residents, what the links send,
  and who sees which control.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Accounts, Journal, Photos}

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    biscuit = resident!(lists, options)

    {:ok,
     organisation: organisation,
     administrator: administrator,
     member: member,
     options: options,
     biscuit: biscuit,
     lists: lists,
     path: ~p"/o/#{organisation.short_name}/residents/#{biscuit.id}/photos",
     conn: sign_in(conn, member)}
  end

  defp add!(context, extra \\ %{}) do
    {:ok, photo} =
      %{resident_id: context.biscuit.id, content: photo()}
      |> Map.merge(extra)
      |> Photos.add_photo(context.options)

    photo
  end

  test "new photos have their caption, and go into the open album", context do
    {:ok, album} =
      Photos.make_album(%{resident_id: context.biscuit.id, name: "Garden"}, context.options)

    {:ok, view, _html} = live(context.conn, "#{context.path}?album=#{album.id}")
    assert has_element?(view, "h2", "Garden")
    assert has_element?(view, ~s(nav[aria-label="Albums"] a[aria-current="page"]), "Garden (0)")

    upload =
      file_input(view, "#add-photos", :photos, [
        %{name: "one.jpg", content: photo(gps: true), type: "image/jpeg"},
        %{name: "two.png", content: photo(format: ".png"), type: "image/png"}
      ])

    assert render_upload(upload, "one.jpg") =~ "one.jpg"
    assert render_upload(upload, "two.png") =~ "two.png"

    {:ok, view, _html} =
      view
      |> form("#add-photos", add: %{caption: "In the garden", taken_on: "2026-11-01"})
      |> render_submit()
      |> follow_redirect(context.conn)

    assert render(view) =~ "The photos are added."
    {:ok, items} = Photos.photos_of(context.biscuit.id, context.options)
    assert length(items) == 2
    assert Enum.all?(items, &(&1.caption == "In the garden" and &1.taken_on == ~D[2026-11-01]))
    assert Enum.all?(items, &(&1.album_ids == [album.id]))

    for item <- items do
      assert has_element?(view, "#item-photo-#{item.photo.id} figcaption", "In the garden")
      assert has_element?(view, "#item-photo-#{item.photo.id} img[alt='In the garden']")
    end

    assert has_element?(view, ~s(a[aria-current="page"]), "Garden (2)")
  end

  test "a file that is not a photo stays out, and the page says why", context do
    {:ok, view, _html} = live(context.conn, context.path)

    upload =
      file_input(view, "#add-photos", :photos, [
        %{name: "fake.jpg", content: <<0xFF, 0xD8, 0xFF>> <> "not a photo", type: "image/jpeg"}
      ])

    render_upload(upload, "fake.jpg")
    view |> form("#add-photos", add: %{caption: ""}) |> render_submit()

    # The form that the person sent says why, and not the top of the page.
    assert has_element?(view, "#add-photos p[role=alert]", "is a photo that Rescord cannot read")
    refute has_element?(view, "main > p[role=alert]")
    assert {:ok, []} = Photos.photos_of(context.biscuit.id, context.options)
  end

  test "a photo of the journal shows with a link to its entry, and its form keeps it",
       context do
    {:ok, entry} =
      Journal.write_entry_with_files(
        %{resident_id: context.biscuit.id, kind: :general, note: "Out in the sun."},
        [{"sun.jpg", photo()}],
        context.options
      )

    {:ok, %{} = by_entry} = Journal.attachments_of([entry.id], context.options)
    [attachment] = by_entry[entry.id]

    {:ok, album} =
      Photos.make_album(%{resident_id: context.biscuit.id, name: "Sun"}, context.options)

    {:ok, view, _html} = live(context.conn, context.path)
    ref = "attachment-#{attachment.id}"

    assert has_element?(
             view,
             ~s(#item-#{ref} a[href$="/journal#entry-#{entry.id}"]),
             "From the journal"
           )

    assert has_element?(
             view,
             ~s(#item-#{ref} img[src="/o/#{context.organisation.short_name}/attachments/#{attachment.id}/thumbnail"])
           )

    # The journal photo has no removal here: it leaves with its entry.
    refute has_element?(view, ~s(#item-#{ref} button[phx-click="remove_photo"]))

    {:ok, view, _html} =
      view
      |> form("#keep-#{ref}",
        photo: %{ref: ref, caption: "Warm", taken_on: "2026-11-02", album_ids: ["", album.id]}
      )
      |> render_submit()
      |> follow_redirect(context.conn)

    assert {:ok, [item]} = Photos.photos_of(context.biscuit.id, context.options)
    assert item.photo.attachment_id == attachment.id
    assert {item.caption, item.taken_on, item.album_ids} == {"Warm", ~D[2026-11-02], [album.id]}
    assert has_element?(view, "#item-photo-#{item.photo.id} figcaption", "Warm")
    assert has_element?(view, "#item-photo-#{item.photo.id} figcaption", "In Sun")
  end

  test "the form of a photo says what it refused, and the other forms do not", context do
    photo = add!(context, %{caption: "Before"})
    other = add!(context)
    {:ok, view, _html} = live(context.conn, context.path)

    # The browser holds the date to today with `max`; a request does not.
    tomorrow = context.organisation |> Accounts.today() |> Date.add(1) |> Date.to_iso8601()

    view
    |> form("#keep-photo-#{photo.id}", photo: %{caption: "After", taken_on: tomorrow})
    |> render_submit()

    assert has_element?(
             view,
             "#keep-photo-#{photo.id} p[role=alert]",
             "Taken on cannot be after today"
           )

    refute has_element?(view, "#keep-photo-#{other.id} p[role=alert]")
    refute has_element?(view, "#add-photos p[role=alert]")
    refute has_element?(view, "main > p[role=alert]")

    # The photo is as it was.
    {:ok, items} = Photos.photos_of(context.biscuit.id, context.options)
    assert Enum.sort(Enum.map(items, & &1.caption)) == [nil, "Before"]
  end

  test "an album that the browser names and the page does not have changes nothing", context do
    photo = add!(context)
    {:ok, view, _html} = live(context.conn, context.path)
    ref = "photo-#{photo.id}"

    # The photo is saved, with no album.
    assert {:error, {:live_redirect, _to}} =
             render_submit(view, "keep", %{
               "photo" => %{
                 "ref" => ref,
                 "caption" => "Seen",
                 "album_ids" => [Ash.UUID.generate()]
               }
             })

    assert {:ok, [%{album_ids: [], caption: "Seen"}]} =
             Photos.photos_of(context.biscuit.id, context.options)

    # A reference that the page does not have changes nothing.
    {:ok, view, _html} = live(context.conn, context.path)
    render_click(view, "make_profile", %{"ref" => "photo-#{Ash.UUID.generate()}"})
    assert {:ok, nil} = Photos.profile_photo(context.biscuit.id, context.options)
  end

  test "the profile picture shows on the page of the resident, and links to its photos",
       context do
    photo = add!(context, %{caption: "Biscuit on the sofa"})
    {:ok, view, _html} = live(context.conn, context.path)

    {:ok, view, _html} =
      view
      |> element(~s(#item-photo-#{photo.id} button[phx-click="make_profile"]))
      |> render_click()
      |> follow_redirect(context.conn)

    assert has_element?(view, "#profile-photo img[alt='Biscuit on the sofa']")
    assert has_element?(view, "#item-photo-#{photo.id} [data-state]", "Profile picture")

    resident_path = ~p"/o/#{context.organisation.short_name}/residents/#{context.biscuit.id}"
    {:ok, resident, _html} = live(context.conn, resident_path)

    assert has_element?(
             resident,
             ~s(#profile-photo img[src="/o/#{context.organisation.short_name}/photos/#{photo.id}/thumbnail"])
           )

    assert has_element?(resident, ~s(a[href="#{context.path}"]), "Photos")

    {:ok, view, _html} = live(context.conn, context.path)

    {:ok, view, _html} =
      view
      |> element(~s(button[phx-click="clear_profile"]))
      |> render_click()
      |> follow_redirect(context.conn)

    refute has_element?(view, "#profile-photo")
  end

  test "the list of the residents shows each profile picture beside the name, or a letter",
       context do
    photo = add!(context)
    {:ok, _profile} = Photos.set_profile_photo(photo, context.options)
    maple = resident!(context.lists, context.options, %{name: "maple"})

    nameless =
      Rescord.Residents.register_resident!(
        %{species_id: context.lists.species.rabbit},
        context.options
      )

    short = context.organisation.short_name
    base = ~p"/o/#{short}/residents"
    portrait = fn resident -> ~s(a[href="#{base}/#{resident.id}"] [data-portrait]) end

    {:ok, view, _html} = live(context.conn, base)
    render_async(view)

    # The picture is decoration: the name alone is the words of the link.
    assert has_element?(view, portrait.(context.biscuit) <> ~s([aria-hidden="true"]))

    assert has_element?(
             view,
             portrait.(context.biscuit) <>
               ~s( img[alt=""][src="/o/#{short}/photos/#{photo.id}/thumbnail"])
           )

    refute has_element?(view, portrait.(maple) <> " img")
    assert has_element?(view, portrait.(maple) <> " span", "M")
    assert has_element?(view, portrait.(nameless))
    refute has_element?(view, portrait.(nameless) <> " img")

    :ok = Photos.remove_photo(photo, context.options)
    {:ok, view, _html} = live(context.conn, base)
    render_async(view)

    refute has_element?(view, "[data-portrait] img")
    assert has_element?(view, portrait.(context.biscuit) <> " span", "B")
  end

  test "a member makes, renames and removes an album", context do
    {:ok, view, _html} = live(context.conn, context.path)
    assert has_element?(view, "p", "No albums yet.")

    {:ok, view, _html} =
      view
      |> form("#make-album", album: %{name: "Recovery"})
      |> render_submit()
      |> follow_redirect(context.conn)

    assert has_element?(view, ~s(a[aria-current="page"]), "Recovery (0)")

    {:ok, view, _html} =
      view
      |> form("#rename-album", album: %{name: "After surgery"})
      |> render_submit()
      |> follow_redirect(context.conn)

    assert has_element?(view, "h2", "After surgery")

    {:ok, view, _html} =
      view
      |> element(~s(button[phx-click="remove_album"]))
      |> render_click()
      |> follow_redirect(context.conn)

    assert has_element?(view, "p", "No albums yet.")
  end

  test "the links send the photo and its thumbnail with their types, to a member alone",
       context do
    photo = add!(context, %{taken_on: ~D[2026-11-03]})
    short = context.organisation.short_name

    conn = get(context.conn, ~p"/o/#{short}/photos/#{photo.id}")
    {:ok, stored} = Rescord.Storage.get(photo.key)
    assert response(conn, 200) == stored
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "sandbox"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(inline; filename="photo-2026-11-03.jpg")
           ]

    conn = get(context.conn, ~p"/o/#{short}/photos/#{photo.id}/thumbnail")
    assert get_resp_header(conn, "content-type") == ["image/webp"]
    assert Rescord.Images.type_of(response(conn, 200)) == "image/webp"

    for path <- [
          ~p"/o/#{short}/photos/#{photo.id}",
          ~p"/o/#{short}/photos/#{photo.id}/thumbnail",
          ~p"/o/#{short}/photos/#{Ash.UUID.generate()}",
          ~p"/o/#{short}/photos/not-an-id"
        ] do
      outsider = build_conn() |> sign_in(user!()) |> get(path)
      assert response(outsider, 404)
    end

    assert response(get(context.conn, ~p"/o/#{short}/photos/not-an-id"), 404)
  end

  test "a role without the power residents sees the photos, and no control", context do
    photo = add!(context)

    {:ok, album} =
      Photos.make_album(%{resident_id: context.biscuit.id, name: "Home"}, context.options)

    {:ok, reader_role} =
      Accounts.define_role(%{name: "Reader", powers: []},
        actor: context.administrator,
        tenant: context.organisation
      )

    {_, reader} = member!(context.organisation, :member, context.administrator)

    {:ok, _member} =
      Accounts.set_member_role(member_of(context, reader), reader_role.id,
        actor: context.administrator,
        tenant: context.organisation
      )

    conn = sign_in(build_conn(), reader)
    {:ok, view, _html} = live(conn, context.path)

    assert has_element?(view, "#item-photo-#{photo.id} img")
    assert has_element?(view, "a", "Home (0)")

    for control <- [
          "#add-photos",
          "#make-album",
          "#keep-photo-#{photo.id}",
          ~s(button[phx-click="make_profile"]),
          ~s(button[phx-click="remove_photo"])
        ] do
      refute has_element?(view, control)
    end

    {:ok, view, _html} = live(conn, "#{context.path}?album=#{album.id}")
    refute has_element?(view, "#rename-album")
    refute has_element?(view, ~s(button[phx-click="remove_album"]))

    # A sent event is refused by the policy too.
    render_click(view, "make_profile", %{"ref" => "photo-#{photo.id}"})
    assert {:ok, nil} = Photos.profile_photo(context.biscuit.id, context.options)
  end

  defp member_of(context, user) do
    {:ok, _organisation, member} =
      Accounts.organisation_for(user, context.organisation.short_name)

    member
  end
end
