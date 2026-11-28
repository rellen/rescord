defmodule RescordWeb.TransferFilePagesTest do
  @moduledoc """
  Holds the pages of the transfers between servers (ADR 0043): the partner
  card and its fingerprint, the record of a card, the download of an
  export, the upload of an import, and a photo of a copy.

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.{Journal, Transfers}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    wattle = organisation!(root, "Wattle Creek")
    banksia = organisation!(root, "Banksia Rise")
    {_, wattle_admin} = member!(wattle, :administrator, root)
    {_, wattle_member} = member!(wattle, :member, wattle_admin)
    {_, banksia_admin} = member!(banksia, :administrator, root)
    {_, banksia_member} = member!(banksia, :member, banksia_admin)
    lists = lists!(wattle, root)
    options = [actor: wattle_admin, tenant: wattle]
    biscuit = resident!(lists, options)

    entry =
      Journal.write_entry!(
        %{resident_id: biscuit.id, kind: :vaccination, vaccine: "A sample vaccine"},
        options
      )

    {:ok, _photo} =
      Journal.attach_file(%{entry_id: entry.id, name: "card.jpg", content: jpeg()}, options)

    {:ok, lawn} =
      Rescord.Photos.add_photo(
        %{resident_id: biscuit.id, content: photo(), caption: "On the lawn"},
        options
      )

    {:ok, _profile} = Rescord.Photos.set_profile_photo(lawn, options)

    {:ok,
     root: root,
     wattle: wattle,
     banksia: banksia,
     wattle_admin: wattle_admin,
     wattle_member: wattle_member,
     banksia_admin: banksia_admin,
     banksia_member: banksia_member,
     biscuit: biscuit}
  end

  defp open(user, path) do
    conn = build_conn() |> sign_in(user)
    {:ok, view, _html} = live(conn, path)
    {conn, view, render_async(view)}
  end

  defp partners!(context) do
    {wattle_card, _} = Transfers.card(context.wattle)
    {banksia_card, _} = Transfers.card(context.banksia)

    {:ok, banksia_there} =
      Transfers.record_remote_partner(context.wattle, banksia_card, actor: context.wattle_admin)

    {:ok, _} =
      Transfers.record_remote_partner(context.banksia, wattle_card, actor: context.banksia_admin)

    banksia_there
  end

  test "an administrator gives the card of the refuge and records the card of another", context do
    {conn, view, _html} = open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/partners")
    {_card, print} = Transfers.card(context.wattle)
    {banksia_card, banksia_print} = Transfers.card(context.banksia)

    assert has_element?(view, "#own-card")
    assert has_element?(view, "#own-fingerprint", print)

    {:ok, view, _html} =
      view
      |> form("#record", remote: %{card: banksia_card})
      |> render_submit()
      |> follow_redirect(conn)

    assert has_element?(view, "tbody td", "Banksia Rise")
    assert has_element?(view, "tbody code", banksia_print)

    # A member reads the partners, and has no card and no form.
    {_conn, view, _html} =
      open(context.wattle_member, ~p"/o/#{context.wattle.short_name}/partners")

    assert has_element?(view, "tbody td", "Banksia Rise")
    refute has_element?(view, "#own-card")
    refute has_element?(view, "#record")
  end

  test "text that is no card gets an answer in words", context do
    {_conn, view, _html} =
      open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/partners")

    view |> form("#record", remote: %{card: "hello"}) |> render_submit()
    assert has_element?(view, "main p[role=alert]", "Card is not a partner card of Rescord")
  end

  test "an export downloads a file, which the other refuge imports and accepts", context do
    partner = partners!(context)

    {_conn, view, _html} =
      open(context.wattle_admin, ~p"/o/#{context.wattle.short_name}/transfers")

    assert has_element?(view, "#export-partner option", "Banksia Rise")

    conn =
      build_conn()
      |> sign_in(context.wattle_admin)
      |> post(~p"/o/#{context.wattle.short_name}/transfers/export", %{
        "export" => %{
          "resident_id" => context.biscuit.id,
          "remote_partner_id" => partner.id,
          "parts" => ["stay", "photos", "no_such_part"],
          "note" => "Shy at first."
        }
      })

    file = response(conn, 200)
    assert <<"RSCD", _rest::binary>> = file
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~r/attachment; filename="biscuit-\d{4}-\d{2}-\d{2}\.rescord"/

    {conn, view, _html} =
      open(context.banksia_admin, ~p"/o/#{context.banksia.short_name}/transfers")

    upload =
      file_input(view, "#import", :transfer_file, [
        %{name: "biscuit.rescord", content: file, type: "application/octet-stream"}
      ])

    render_upload(upload, "biscuit.rescord")

    {:ok, view, _html} =
      view |> form("#import") |> render_submit() |> follow_redirect(conn)

    assert has_element?(view, "#received tbody td", "Biscuit")
    assert has_element?(view, "#received tbody td", "Wattle Creek")
    [transfer] = Transfers.transfers!(actor: context.banksia_admin)
    assert transfer.parts == [:stay, :photos]

    {:ok, _view, _html} =
      view |> render_click("accept", %{"id" => transfer.id}) |> follow_redirect(conn)

    # A member there reads the copy, with its photo.
    {_conn, view, _html} =
      open(context.banksia_member, ~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}")

    assert has_element?(view, "p", "A copy from Wattle Creek")
    assert has_element?(view, "h2", "Stay at Wattle Creek")
    [%{"files" => [photo]}] = transfer.snapshot["medical"]
    assert has_element?(view, "a", "card.jpg")

    # The photos of the copy: the photo of the journal and the photo with a
    # caption, which is the profile picture, each as its thumbnail.
    assert has_element?(view, "h2", "Photos")
    assert has_element?(view, "#copy-photo-list figcaption", "On the lawn")
    assert has_element?(view, "#copy-profile-photo img[alt='On the lawn']")

    %{"photos" => photos, "profile" => profile} = transfer.snapshot["photos"]
    assert length(photos) == 2
    %{"thumbnail" => %{"id" => thumbnail_id}} = Enum.find(photos, &(&1["id"] == profile))

    thumbnail =
      ~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}/files/#{thumbnail_id}"

    assert has_element?(view, "#copy-photo-#{profile} img[src='#{thumbnail}']")
    conn = build_conn() |> sign_in(context.banksia_member) |> get(thumbnail)
    assert <<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>> = response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["image/webp"]

    conn =
      build_conn()
      |> sign_in(context.banksia_member)
      |> get(~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}/files/#{photo["id"]}")

    assert response(conn, 200) == stored_jpeg()
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "sandbox"

    # Nobody else reads the photo, and a file that the copy does not name is no page.
    path = ~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}/files/#{photo["id"]}"
    assert response(get(build_conn() |> sign_in(context.wattle_member), path), 404)

    assert response(
             get(
               build_conn() |> sign_in(context.banksia_member),
               ~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}/files/#{Ash.UUID.generate()}"
             ),
             404
           )
  end

  test "a refused import says why, and a refused export goes back with the words", context do
    partner = partners!(context)

    {_conn, view, _html} =
      open(context.banksia_admin, ~p"/o/#{context.banksia.short_name}/transfers")

    upload =
      file_input(view, "#import", :transfer_file, [
        %{name: "odd.rescord", content: "not a transfer file", type: "application/octet-stream"}
      ])

    render_upload(upload, "odd.rescord")
    view |> form("#import") |> render_submit()
    assert has_element?(view, "main p[role=alert]", "File is not a transfer file of Rescord")

    conn =
      build_conn()
      |> sign_in(context.wattle_admin)
      |> post(~p"/o/#{context.wattle.short_name}/transfers/export", %{
        "export" => %{"resident_id" => Ash.UUID.generate(), "remote_partner_id" => partner.id}
      })

    assert redirected_to(conn) == ~p"/o/#{context.wattle.short_name}/transfers"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "is not a resident of this refuge"
  end

  test "a member has no export and no import, and the controller refuses them", context do
    partner = partners!(context)

    {_conn, view, _html} =
      open(context.wattle_member, ~p"/o/#{context.wattle.short_name}/transfers")

    refute has_element?(view, "#export")
    refute has_element?(view, "#import")

    conn =
      build_conn()
      |> sign_in(context.wattle_member)
      |> post(~p"/o/#{context.wattle.short_name}/transfers/export", %{
        "export" => %{"resident_id" => context.biscuit.id, "remote_partner_id" => partner.id}
      })

    assert redirected_to(conn) == ~p"/o/#{context.wattle.short_name}/transfers"

    # A person of another refuge gets no page.
    conn =
      build_conn()
      |> sign_in(context.banksia_admin)
      |> post(~p"/o/#{context.wattle.short_name}/transfers/export", %{"export" => %{}})

    assert response(conn, 404)
  end
end
