defmodule RescordWeb.PhotoPagesTest do
  @moduledoc """
  Holds the photos of a resident on the pages (ADR 0055): the page of the
  photos with the photos of the journal, new photos with their caption and
  album, the form of a photo, the albums, the profile picture on the page
  of the resident and in the list of the residents, what the links send,
  and who sees which control.

  The tests find what a person finds (ADR 0107). A card of a photo is
  found by its id, as two photos with no caption of one day have the same
  words.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_async: 1, render_click: 3, render_submit: 3]
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

  # A file to choose, in the folder of the test.
  defp file!(context, name, content) do
    path = Path.join(context.tmp_dir, name)
    File.write!(path, content)
    path
  end

  defp card(%Photos.Photo{id: id}), do: "#item-photo-#{id}"
  defp card(ref) when is_binary(ref), do: "#item-#{ref}"

  # The album that the page shows is the current link of the albums.
  defp current_album(session, words) do
    within(session, navigation("Albums"), &assert_has(&1, "[aria-current=page]", text: words))
  end

  test "new photos have their caption, and go into the open album", context do
    {:ok, album} =
      Photos.make_album(%{resident_id: context.biscuit.id, name: "Garden"}, context.options)

    session =
      context.conn
      |> visit("#{context.path}?album=#{album.id}")
      |> assert_has(main() |> region("Garden"))
      |> current_album("Garden (0)")
      |> upload("Choose photos", file!(context, "one.jpg", photo(gps: true)))
      |> upload("Choose photos", file!(context, "two.png", photo(format: ".png")))
      |> assert_has(region("Garden") |> button("Take out one.jpg"))
      |> assert_has(region("Garden") |> button("Take out two.png"))
      |> fill_in("Caption", with: "In the garden")
      |> fill_in("Date", with: "2026-11-01")
      |> click_button("Add the photos")
      |> assert_has(status(), text: "The photos are added.")

    {:ok, items} = Photos.photos_of(context.biscuit.id, context.options)
    assert length(items) == 2
    assert Enum.all?(items, &(&1.caption == "In the garden" and &1.taken_on == ~D[2026-11-01]))
    assert Enum.all?(items, &(&1.album_ids == [album.id]))

    for item <- items do
      within(session, card(item.photo), fn card ->
        card
        |> assert_has("figcaption", text: "In the garden")
        |> assert_has(image("In the garden"))
      end)
    end

    current_album(session, "Garden (2)")
  end

  test "a file that is not a photo stays out, and the page says why", context do
    fake = file!(context, "fake.jpg", <<0xFF, 0xD8, 0xFF>> <> "not a photo")

    context.conn
    |> visit(context.path)
    |> upload("Choose photos", fake)
    |> click_button("Add the photos")
    # The form that the person sent says why, and not the top of the page.
    |> within(
      "#add-photos",
      &assert_has(&1, alert(), text: "is a photo that Rescord cannot read")
    )
    |> refute_has("main > [role=alert]")

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

    short = context.organisation.short_name
    session = visit(context.conn, context.path)
    sun = card("attachment-#{attachment.id}")

    assert href(session, link("From the journal")) =~ ~r"/journal\?entry=#{entry.id}$"

    assert src(session, image(~r/^A photo of Biscuit/)) ==
             "/o/#{short}/attachments/#{attachment.id}/thumbnail"

    # The photo opens as its display file, and "Full size" opens the file
    # (issue 34).
    assert_has(
      session,
      "#{sun} figure > a[href=\"/o/#{short}/attachments/#{attachment.id}/display\"]"
    )

    assert href(session, link("Full size")) == "/o/#{short}/attachments/#{attachment.id}"

    session =
      session
      # The journal photo has no removal here: it leaves with its entry.
      |> within(sun, &refute_has(&1, button("Remove")))
      |> within(sun, fn card ->
        card
        |> fill_in("Caption", with: "Warm")
        |> fill_in("Date", with: "2026-11-02")
        |> check("Sun")
        |> click_button("Save")
      end)

    assert {:ok, [item]} = Photos.photos_of(context.biscuit.id, context.options)
    assert item.photo.attachment_id == attachment.id
    assert {item.caption, item.taken_on, item.album_ids} == {"Warm", ~D[2026-11-02], [album.id]}

    within(session, card(item.photo), fn card ->
      card
      |> assert_has("figcaption", text: "Warm")
      |> assert_has("figcaption", text: "In Sun")
    end)
  end

  test "the form of a photo says what it refused, and the other forms do not", context do
    photo = add!(context, %{caption: "Before"})
    other = add!(context)

    # The browser holds the date to today with `max`; a request does not.
    tomorrow = context.organisation |> Accounts.today() |> Date.add(1) |> Date.to_iso8601()

    context.conn
    |> visit(context.path)
    |> within(card(photo), fn card ->
      card
      |> fill_in("Caption", with: "After")
      |> fill_in("Date", with: tomorrow)
      |> click_button("Save")
    end)
    |> within(card(photo), &assert_has(&1, alert(), text: "Taken on cannot be after today"))
    |> within(card(other), &refute_has(&1, alert()))
    |> within("#add-photos", &refute_has(&1, alert()))
    |> refute_has("main > [role=alert]")

    # The photo is as it was.
    {:ok, items} = Photos.photos_of(context.biscuit.id, context.options)
    assert Enum.sort(Enum.map(items, & &1.caption)) == [nil, "Before"]
  end

  test "an album that the browser names and the page does not have changes nothing", context do
    photo = add!(context)
    ref = "photo-#{photo.id}"

    # The photo is saved, with no album.
    context.conn
    |> visit(context.path)
    |> unwrap(
      &render_submit(&1, "keep", %{
        "photo" => %{"ref" => ref, "caption" => "Seen", "album_ids" => [Ash.UUID.generate()]}
      })
    )
    |> assert_path(context.path)

    assert {:ok, [%{album_ids: [], caption: "Seen"}]} =
             Photos.photos_of(context.biscuit.id, context.options)

    # A reference that the page does not have changes nothing.
    context.conn
    |> visit(context.path)
    |> unwrap(&render_click(&1, "make_profile", %{"ref" => "photo-#{Ash.UUID.generate()}"}))

    assert {:ok, nil} = Photos.profile_photo(context.biscuit.id, context.options)
  end

  test "the profile picture shows on the page of the resident, and links to its photos",
       context do
    photo = add!(context, %{caption: "Biscuit on the sofa"})
    short = context.organisation.short_name
    profile = main() |> figure("Profile picture") |> image("Biscuit on the sofa")

    context.conn
    |> visit(context.path)
    |> refute_has(profile)
    |> within(card(photo), &click_button(&1, "Make it the profile picture"))
    |> assert_has(profile)
    |> within(card(photo), &assert_has(&1, "figcaption strong", text: "Profile picture"))

    resident = visit(context.conn, ~p"/o/#{short}/residents/#{context.biscuit.id}")
    assert src(resident, profile) == "/o/#{short}/photos/#{photo.id}/thumbnail"
    assert href(resident, main() |> link("Photos")) == context.path

    context.conn
    |> visit(context.path)
    |> click(button("No profile picture"))
    |> refute_has(main() |> figure("Profile picture"))
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

    session = context.conn |> visit(base) |> unwrap(&render_async/1)

    # The picture is decoration: the name alone is the words of the link.
    session
    |> assert_has(main() |> link("Biscuit"))
    |> assert_has(main() |> link("maple"))
    |> assert_has(main() |> link("A resident with no name"))
    |> assert_has(portrait.(context.biscuit) <> ~s([aria-hidden="true"]))
    |> assert_has(
      portrait.(context.biscuit) <>
        ~s( img[alt=""][src="/o/#{short}/photos/#{photo.id}/thumbnail"])
    )
    |> refute_has(portrait.(maple) <> " img")
    |> assert_has(portrait.(maple) <> " span", text: "M")
    |> assert_has(portrait.(nameless))
    |> refute_has(portrait.(nameless) <> " img")

    :ok = Photos.remove_photo(photo, context.options)

    context.conn
    |> visit(base)
    |> unwrap(&render_async/1)
    |> refute_has("[data-portrait] img")
    |> assert_has(portrait.(context.biscuit) <> " span", text: "B")
  end

  test "a member makes, renames and removes an album", context do
    context.conn
    |> visit(context.path)
    |> assert_has(region("Albums"), text: "No album yet.")
    |> fill_in("Name of the album", with: "Recovery")
    |> click_button("Make the album")
    |> assert_has(status(), text: "The album is made.")
    |> current_album("Recovery (0)")
    |> fill_in("New name of the album", with: "After surgery")
    |> click_button("Rename")
    |> assert_has(main() |> region("After surgery"))
    |> click(button("Remove the album After surgery"))
    |> assert_has(region("Albums"), text: "No album yet.")
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
    # Its bytes never change, so the browser keeps it (issue 34).
    assert get_resp_header(conn, "cache-control") == [RescordWeb.FileCache.kept()]
    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "sandbox"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(inline; filename="photo-2026-11-03.jpg")
           ]

    conn = get(context.conn, ~p"/o/#{short}/photos/#{photo.id}/thumbnail")
    assert get_resp_header(conn, "content-type") == ["image/webp"]
    assert get_resp_header(conn, "cache-control") == [RescordWeb.FileCache.kept()]
    assert Rescord.Images.type_of(response(conn, 200)) == "image/webp"

    # The display file, which a page opens (issue 34).
    conn = get(context.conn, ~p"/o/#{short}/photos/#{photo.id}/display")
    assert {:ok, display} = Rescord.Storage.get(photo.display_key)
    assert response(conn, 200) == display
    assert get_resp_header(conn, "content-type") == ["image/webp"]
    assert get_resp_header(conn, "cache-control") == [RescordWeb.FileCache.kept()]

    assert get_resp_header(conn, "content-disposition") == [
             ~s(inline; filename="photo-2026-11-03.webp")
           ]

    for path <- [
          ~p"/o/#{short}/photos/#{photo.id}",
          ~p"/o/#{short}/photos/#{photo.id}/thumbnail",
          ~p"/o/#{short}/photos/#{photo.id}/display",
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

    session =
      conn
      |> visit(context.path)
      |> assert_has(main() |> image(~r/^A photo of Biscuit/))
      |> assert_has(navigation("Albums") |> link("Home (0)"))

    for control <- [
          "Add the photos",
          "Make the album",
          "Save",
          "Make it the profile picture",
          "Remove"
        ] do
      refute_has(session, main() |> button(control))
    end

    conn
    |> visit("#{context.path}?album=#{album.id}")
    |> refute_has(main() |> button("Rename"))
    |> refute_has(main() |> button("Remove the album Home"))
    # A sent event is refused by the policy too.
    |> unwrap(&render_click(&1, "make_profile", %{"ref" => "photo-#{photo.id}"}))

    assert {:ok, nil} = Photos.profile_photo(context.biscuit.id, context.options)
  end

  defp member_of(context, user) do
    {:ok, _organisation, member} =
      Accounts.organisation_for(user, context.organisation.short_name)

    member
  end
end
