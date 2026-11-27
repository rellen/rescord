defmodule RescordWeb.Features.PhotosTest do
  @moduledoc """
  Adds a photo of a resident through a real browser (ADR 0055).

  `RescordWeb.PhotoPagesTest` holds each rule of the page. This test holds
  what only a browser shows: that the browser sends a file that a person
  chooses by the words of the control, that the thumbnail which the page
  names is an image that the browser draws, that a refusal shows in the
  form that the person sent, which stays open, and that a file with a long
  name does not make the page wider than a phone.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  @moduletag :tmp_dir

  # A phone camera gives a file a long name with no space.
  @file_name "IMG_20261101_093011_from_the_camera_of_a_phone.jpg"

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_member, user} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    biscuit = resident!(lists, actor: root, tenant: organisation)

    # The photo that the member chooses is a file of the machine of the
    # browser. It is beside the store of the test, and not in it.
    from_the_phone = Path.join(tmp_dir, "from-the-phone")
    File.mkdir_p!(from_the_phone)
    file = Path.join(from_the_phone, @file_name)
    File.write!(file, photo(width: 640, height: 480, gps: true))

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok,
     address: to_string(user.email),
     path: "/o/#{organisation.short_name}/residents/#{biscuit.id}/photos",
     chosen: file}
  end

  test "a member adds a photo, and makes it the profile picture",
       %{conn: session, address: address, path: path, chosen: file} do
    session
    |> sign_in_with_link(address)
    |> visit(path)
    |> assert_connected()
    |> assert_has("#no-photos", text: "No photos here yet.")
    # The form is closed until the member opens it.
    |> click("summary", "Add photos")
    # A refusal shows in the form, and the form stays open.
    |> click_button("Add the photos")
    |> assert_has("#add-photos p[role=alert]", text: "Choose a photo to add")
    |> upload("Choose photos", file)
    |> assert_has("#add-photos-files li", text: @file_name)
    |> fill_in("Caption (optional)", with: "In the garden")
    |> click_button("Add the photos")
    |> assert_has("#photos figcaption", text: "In the garden")
    |> assert_connected()
    |> assert_drawn("#photos img[alt='In the garden']")

    session
    |> click_button("Make it the profile picture")
    |> assert_has("#photos [data-state=info]", text: "Profile picture")
    |> assert_connected()
    |> assert_drawn("#profile-photo img")
    # The page of the resident shows the picture too. Its title is the name
    # alone: the title of the page of the photos has the name in it.
    |> click_link("nav[aria-label=Breadcrumb] a", "Biscuit")
    |> assert_has("h1", text: "Biscuit", exact: true)
    |> assert_has("h2", text: "About")
    |> assert_drawn("#profile-photo img[alt='In the garden']")
  end

  @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
  test "on a phone, a photo with a long name stays inside the page",
       %{conn: session, address: address, path: path, chosen: file} do
    session
    |> sign_in_with_link(address)
    |> visit(path)
    |> assert_connected()
    |> click("summary", "Add photos")
    |> upload("Choose photos", file)
    |> assert_has("#add-photos-files li", text: @file_name)
    # The page is as wide as the screen: nothing in it pushes it wider.
    |> evaluate(
      "document.documentElement.scrollWidth - document.documentElement.clientWidth",
      fn wider -> assert wider == 0 end
    )
    |> evaluate(
      """
      (() => {
        const within = document.querySelector("#add-photos-files").getBoundingClientRect();
        return Array.from(document.querySelectorAll("#add-photos-files li, #add-photos-files li *"))
          .every((part) => part.getBoundingClientRect().right <= within.right);
      })()
      """,
      fn inside? -> assert inside?, "a part of a chosen file is outside its form" end
    )
  end

  # The browser has the image of `selector`, and can draw it: an image that
  # did not arrive, or that the browser cannot read, has no width.
  defp assert_drawn(session, selector) do
    session
    |> assert_has(selector)
    |> evaluate(
      """
      (async () => {
        const image = document.querySelector(#{inspect(selector)});
        await image.decode();
        return image.naturalWidth;
      })()
      """,
      fn width -> assert width > 0, "the browser did not draw #{selector}" end
    )
  end
end
