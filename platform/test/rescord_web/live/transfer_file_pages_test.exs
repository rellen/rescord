defmodule RescordWeb.TransferFilePagesTest do
  @moduledoc """
  Holds the pages of the transfers between servers (ADR 0043): the partner
  card and its fingerprint, the record of a card, the download of an
  export, the upload of an import, and a photo of a copy. The tests find what a person finds (ADR 0107).

  Each test creates organisations, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

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

  defp visit_as(user, path), do: build_conn() |> sign_in(user) |> visit(path)

  defp remote, do: main() |> region("Refuges on other servers")
  defp received, do: main() |> region("Received")

  # A file on the disk, for an upload of the page.
  defp file!(context, name, content) do
    path = Path.join(context.tmp_dir, name)
    File.write!(path, content)
    path
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
    partners = ~p"/o/#{context.wattle.short_name}/partners"
    {card, print} = Transfers.card(context.wattle)
    {banksia_card, banksia_print} = Transfers.card(context.banksia)

    session = visit_as(context.wattle_admin, partners)
    assert value(session, remote() |> field("Partner card")) == card

    session
    |> assert_has(remote(), text: "Fingerprint: #{print}")
    |> fill_in("The partner card of the other refuge", with: banksia_card)
    |> click(button("Record the partner"))
    |> assert_has(remote() |> row(~r/^Banksia Rise\b/), text: banksia_print)

    # A member reads the partners, and has no card and no form.
    context.wattle_member
    |> visit_as(partners)
    |> assert_has(remote() |> row(~r/^Banksia Rise\b/))
    |> refute_has(remote() |> field("Partner card"))
    |> refute_has(remote() |> button("Record the partner"))
  end

  test "text that is no card gets an answer in words", context do
    context.wattle_admin
    |> visit_as(~p"/o/#{context.wattle.short_name}/partners")
    |> fill_in("The partner card of the other refuge", with: "hello")
    |> click(button("Record the partner"))
    |> assert_has(main() |> alert(), text: "Card is not a partner card of Rescord")
  end

  test "an export downloads a file, which the other refuge imports and accepts", context do
    partner = partners!(context)

    context.wattle_admin
    |> visit_as(~p"/o/#{context.wattle.short_name}/transfers")
    |> assert_has(
      main()
      |> region("Send a resident to a refuge on another server")
      |> field("Partner on another server"),
      text: "Banksia Rise"
    )

    # The file comes from a controller, so the test posts the form.
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

    context.banksia_admin
    |> visit_as(~p"/o/#{context.banksia.short_name}/transfers")
    |> upload("Transfer file", file!(context, "biscuit.rescord", file))
    |> click(button("Import the file"))
    |> assert_has(received() |> row(~r/^Biscuit\b/), text: "Wattle Creek")
    |> click(received() |> row(~r/^Biscuit\b/) |> button("Accept the transfer of Biscuit"))

    [transfer] = Transfers.transfers!(actor: context.banksia_admin)
    assert transfer.parts == [:stay, :photos]
    assert transfer.state == :accepted

    # A member there reads the copy, with its photo.
    session =
      context.banksia_member
      |> visit_as(~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}")
      |> assert_has(main(), text: "A copy from Wattle Creek")
      |> assert_has(main() |> region("Stay at Wattle Creek"))
      |> assert_has(main() |> list("Files of the entry") |> link("card.jpg"))

    [%{"files" => [photo]}] = transfer.snapshot["medical"]

    # The photos of the copy: the photo of the journal and the photo with a
    # caption, which is the profile picture, each as its thumbnail.
    photos = main() |> region("Photos")
    %{"photos" => list, "profile" => profile} = transfer.snapshot["photos"]
    assert length(list) == 2
    %{"thumbnail" => %{"id" => thumbnail_id}} = Enum.find(list, &(&1["id"] == profile))

    thumbnail =
      ~p"/o/#{context.banksia.short_name}/transfers/#{transfer.id}/files/#{thumbnail_id}"

    assert_has(session, photos |> figure("Profile picture") |> image("On the lawn"))
    assert src(session, photos |> figure(~r/^On the lawn\b/) |> image("On the lawn")) == thumbnail

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

    context.banksia_admin
    |> visit_as(~p"/o/#{context.banksia.short_name}/transfers")
    |> upload("Transfer file", file!(context, "odd.rescord", "not a transfer file"))
    |> click(button("Import the file"))
    |> assert_has(main() |> alert(), text: "File is not a transfer file of Rescord")

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

    context.wattle_member
    |> visit_as(~p"/o/#{context.wattle.short_name}/transfers")
    |> assert_has(main() |> heading(level: 1), text: "Transfers")
    |> refute_has(main() |> region("Send a resident to a refuge on another server"))
    |> refute_has(main() |> region("Import a transfer file"))

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
