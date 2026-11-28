defmodule RescordWeb.AttachmentPagesTest do
  @moduledoc """
  Holds the files of the journal on the pages (ADR 0041): a new entry with
  its files, a file that the form refuses, the link of each file and what
  it sends, who reads a file, and who takes one off.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  require Ecto.Query

  alias Rescord.Journal

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

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp entries(context) do
    {:ok, entries} = Journal.entries(context.biscuit.id, context.options)
    entries
  end

  defp files(view, files) do
    file_input(
      view,
      "#entry",
      :files,
      for({name, content, type} <- files, do: %{name: name, content: content, type: type})
    )
  end

  test "a new entry has the files of its form, and each file opens from its link", context do
    {view, _html} = open(context.conn, context.path)

    upload =
      files(view, [
        {"biscuit.jpg", jpeg(), "image/jpeg"},
        {"report.pdf", pdf(), "application/pdf"}
      ])

    assert render_upload(upload, "biscuit.jpg") =~ "biscuit.jpg"
    assert render_upload(upload, "report.pdf") =~ "report.pdf"

    {:ok, view, _html} =
      view
      |> form("#entry", entry: %{kind: "general", note: "Weighed, with a photo."})
      |> render_submit()
      |> follow_redirect(context.conn)

    [entry] = entries(context)
    {:ok, %{} = by_entry} = Journal.attachments_of([entry.id], context.options)
    photo = Enum.find(by_entry[entry.id], &(&1.name == "biscuit.jpg"))
    report = Enum.find(by_entry[entry.id], &(&1.name == "report.pdf"))

    assert has_element?(view, "#attachment-#{photo.id} a", "biscuit.jpg")
    assert has_element?(view, "#attachment-#{report.id} a", "report.pdf")

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
    {view, _html} = open(context.conn, context.path)

    # The name says PDF, and the first bytes say otherwise.
    upload = files(view, [{"report.pdf", "<html>not a pdf</html>", "application/pdf"}])
    render_upload(upload, "report.pdf")

    html =
      view
      |> form("#entry", entry: %{kind: "general", note: "With a file."})
      |> render_submit()

    assert html =~ "is not a photo or a PDF"
    assert entries(context) == []
  end

  test "the form refuses a file that is not a photo or a PDF by its name", context do
    {view, _html} = open(context.conn, context.path)
    upload = files(view, [{"notes.html", "<html></html>", "text/html"}])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "notes.html")
  end

  test "the form says what to do with a HEIC photo that it refuses (issue 34)", context do
    {view, _html} = open(context.conn, context.path)
    upload = files(view, [{"IMG_0042.HEIC", "not read", "image/heic"}])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "IMG_0042.HEIC")
    assert render(view) =~ "Rescord cannot read HEIC or AVIF photos"
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

    {:ok, own} =
      Journal.attach_file(%{entry_id: entry.id, name: "own.pdf", content: pdf()}, context.options)

    {:ok, theirs} =
      Journal.attach_file(%{entry_id: entry.id, name: "theirs.pdf", content: pdf()},
        actor: context.administrator,
        tenant: context.organisation
      )

    {view, _html} = open(context.conn, context.path)
    assert has_element?(view, "#attachment-#{own.id} button", "Take off")
    refute has_element?(view, "#attachment-#{theirs.id} button")

    # An event that the page did not offer is refused.
    render_click(view, "remove_attachment", %{"id" => theirs.id})
    assert has_element?(view, "main p[role=alert]")

    {:ok, view, _html} =
      view
      |> render_click("remove_attachment", %{"id" => own.id})
      |> follow_redirect(context.conn)

    refute has_element?(view, "#attachment-#{own.id}")
    assert has_element?(view, "#attachment-#{theirs.id}")
  end
end
