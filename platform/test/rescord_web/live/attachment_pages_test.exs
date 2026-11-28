defmodule RescordWeb.AttachmentPagesTest do
  @moduledoc """
  Holds the files of the journal on the pages (ADR 0041): a new entry with
  its files, a file that the form refuses, the link of each file and what
  it sends, who reads a file, and who takes one off. The page tests find
  what a person finds (ADR 0107); what a file sends is a response, not a
  page.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest,
    only: [file_input: 4, render: 1, render_async: 1, render_click: 3, render_upload: 2]

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  require Ecto.Query

  alias Rescord.Journal
  alias Rescord.Storage.Scan

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
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     options: options,
     biscuit: biscuit,
     path: ~p"/o/#{organisation.short_name}/residents/#{biscuit.id}/journal",
     conn: sign_in(conn, member)}
  end

  # The page lists its entries with Cinder, which loads them after the
  # first render.
  defp open(conn, path), do: conn |> visit(path) |> unwrap(&render_async/1)

  defp new_entry, do: main() |> details("New journal entry")
  defp chosen, do: new_entry() |> group(~r/^Files:/)

  defp files_of(kind),
    do: main() |> region("Entries") |> article(kind) |> region("Files of the entry")

  # A file on the disk, for an upload of the page.
  defp file!(context, name, content) do
    path = Path.join(context.tmp_dir, name)
    File.write!(path, content)
    path
  end

  # A general entry with the files that the session chose.
  defp write_general(session, note) do
    session
    |> within(new_entry(), fn form ->
      form
      |> select("Kind", option: "General")
      |> fill_in("What happened", with: note)
    end)
    |> click(button("Write the entry"))
    |> unwrap(&render_async/1)
  end

  # A file that the form refuses by its name. PhoenixTest raises for it, so
  # the test sends it as the browser does, and reads the page after.
  defp choose_refused(session, name, content, type) do
    unwrap(session, fn view ->
      upload = file_input(view, "#entry", :files, [%{name: name, content: content, type: type}])
      assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, name)
      render(view)
    end)
  end

  defp entries(context) do
    {:ok, entries} = Journal.entries(context.biscuit.id, context.options)
    entries
  end

  test "a new entry has the files of its form, and each file opens from its link", context do
    session =
      context.conn
      |> open(context.path)
      |> upload("Choose files", file!(context, "biscuit.jpg", jpeg()))
      |> upload("Choose files", file!(context, "report.pdf", pdf()))
      |> assert_has(chosen() |> item(~r/^biscuit\.jpg\b/))
      |> assert_has(chosen() |> item(~r/^report\.pdf\b/))
      |> write_general("Weighed, with a photo.")

    [entry] = entries(context)
    {:ok, %{} = by_entry} = Journal.attachments_of([entry.id], context.options)
    photo = Enum.find(by_entry[entry.id], &(&1.name == "biscuit.jpg"))
    report = Enum.find(by_entry[entry.id], &(&1.name == "report.pdf"))

    assert has?(session, files_of(~r/^General\b/) |> link("biscuit.jpg"))

    assert href(session, files_of(~r/^General\b/) |> link("report.pdf")) ==
             ~p"/o/#{context.organisation.short_name}/attachments/#{report.id}"

    conn = get(context.conn, ~p"/o/#{context.organisation.short_name}/attachments/#{photo.id}")
    assert response(conn, 200) == stored_jpeg()
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == [RescordWeb.FileCache.kept()]
    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "sandbox"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(inline; filename="biscuit.jpg"; filename*=UTF-8''biscuit.jpg)
           ]
  end

  test "a file of another type writes no entry, and says why", context do
    # The name says PDF, and the first bytes say otherwise.
    context.conn
    |> open(context.path)
    |> upload("Choose files", file!(context, "report.pdf", "<html>not a pdf</html>"))
    |> write_general("With a file.")
    |> assert_has(main() |> alert(), text: "is not a photo or a PDF")

    assert entries(context) == []
  end

  test "with the virus scan on, a PDF that clamd finds or cannot scan writes no entry (issue 37)",
       context do
    send_pdf = fn ->
      context.conn
      |> open(context.path)
      |> upload("Choose files", file!(context, "report.pdf", pdf()))
      |> write_general("With a file.")
    end

    root = root!()
    address = Rescord.FakeClamd.start({:found, "Win.Test.EICAR_HDB-1"})
    {:ok, _settings} = Scan.save_settings(%{scan_on: true, address: address}, actor: root)

    ExUnit.CaptureLog.capture_log(fn ->
      assert_has(send_pdf.(), main() |> alert(),
        text: "holds something that the virus scan found harmful"
      )

      assert_received {:clamd_scanned, _bytes}

      {:ok, _settings} =
        Scan.save_settings(%{address: Rescord.FakeClamd.nobody()}, actor: root)

      assert_has(send_pdf.(), main() |> alert(),
        text: "could not be checked for viruses. Try again later"
      )
    end)

    assert entries(context) == []
  end

  test "the form refuses a file that is not a photo or a PDF by its name", context do
    context.conn
    |> open(context.path)
    |> choose_refused("notes.html", "<html></html>", "text/html")
    |> assert_has(chosen() |> item(~r/^notes\.html\b/) |> alert(),
      text: "Rescord takes a photo or a PDF"
    )
  end

  test "the form says what to do with a HEIC photo that it refuses (issue 34)", context do
    context.conn
    |> open(context.path)
    |> choose_refused("IMG_0042.HEIC", "not read", "image/heic")
    |> assert_has(chosen() |> item(~r/^IMG_0042\.HEIC\b/) |> alert(),
      text: "Rescord cannot read HEIC or AVIF photos"
    )
  end

  test "a file opens for each member, and for nobody outside the organisation", context do
    entry =
      Journal.write_entry!(
        %{resident_id: context.biscuit.id, kind: :general, note: "x"},
        context.options
      )

    {:ok, attachment} =
      Journal.attach_file(%{entry_id: entry.id, name: "a.pdf", content: pdf()}, context.options)

    path = ~p"/o/#{context.organisation.short_name}/attachments/#{attachment.id}"

    assert response(get(build_conn() |> sign_in(context.administrator), path), 200) == pdf()

    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    assert response(get(build_conn() |> sign_in(outsider), path), 404)
    assert response(get(build_conn(), path), 404)

    # An id that is no attachment, and one that is no id, look the same.
    assert response(
             get(
               context.conn,
               ~p"/o/#{context.organisation.short_name}/attachments/#{Ash.UUID.generate()}"
             ),
             404
           )

    assert response(
             get(context.conn, "/o/#{context.organisation.short_name}/attachments/not-an-id"),
             404
           )
  end

  test "the browser keeps a file, but a journal photo that the job has not cleaned (issue 34)",
       context do
    entry =
      Journal.write_entry!(
        %{resident_id: context.biscuit.id, kind: :general, note: "x"},
        context.options
      )

    attach = fn name, content ->
      {:ok, attachment} =
        Journal.attach_file(%{entry_id: entry.id, name: name, content: content}, context.options)

      attachment
    end

    report = attach.("a.pdf", pdf())
    old = attach.("old.jpg", jpeg())
    {:ok, photo} = Rescord.Photos.adopt(old.id, context.options)

    # As Rescord 0.1.0 kept it: no thumbnail, which the job of the images
    # writes when it cleans the photo (ADR 0109).
    prefix = "org_" <> context.organisation.id

    for {table, column} <- [{"journal_attachments", :id}, {"photos", :attachment_id}] do
      Ecto.Query.from(row in table, where: field(row, ^column) == type(^old.id, Ecto.UUID))
      |> Rescord.Repo.update_all([set: [thumbnail_key: nil, display_key: nil]], prefix: prefix)
    end

    short = context.organisation.short_name

    cache_of = fn path ->
      conn = get(context.conn, path)
      assert response(conn, 200)
      get_resp_header(conn, "cache-control")
    end

    assert cache_of.(~p"/o/#{short}/attachments/#{report.id}") == [RescordWeb.FileCache.kept()]
    assert cache_of.(~p"/o/#{short}/attachments/#{old.id}") == [RescordWeb.FileCache.none()]
    assert cache_of.(~p"/o/#{short}/photos/#{photo.id}") == [RescordWeb.FileCache.none()]
  end

  test "a member takes off their own file, and has no button for another", context do
    entry =
      Journal.write_entry!(
        %{resident_id: context.biscuit.id, kind: :general, note: "x"},
        context.options
      )

    {:ok, _own} =
      Journal.attach_file(%{entry_id: entry.id, name: "own.pdf", content: pdf()}, context.options)

    {:ok, theirs} =
      Journal.attach_file(%{entry_id: entry.id, name: "theirs.pdf", content: pdf()},
        actor: context.administrator,
        tenant: context.organisation
      )

    own = files_of(~r/^General\b/) |> item(~r/^own\.pdf\b/)
    other = files_of(~r/^General\b/) |> item(~r/^theirs\.pdf\b/)

    context.conn
    |> open(context.path)
    |> assert_has(own |> details("Take off own.pdf"))
    |> refute_has(other |> details(~r/^Take off/))
    |> refute_has(other |> button(~r/^Take off/))
    # An event that the page did not offer is refused.
    |> unwrap(&render_click(&1, "remove_attachment", %{"id" => theirs.id}))
    |> assert_has(main() |> alert())
    |> click(own |> button("Take off the file own.pdf"))
    |> unwrap(&render_async/1)
    |> refute_has(own)
    |> assert_has(other)
  end
end
