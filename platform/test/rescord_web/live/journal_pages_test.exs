defmodule RescordWeb.JournalPagesTest do
  @moduledoc """
  Holds the page of the journal of a resident: who can open it, what the
  form of an entry does for each kind, and who can correct an entry.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Journal

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    {_, other} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    biscuit = resident!(lists, options)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     other: other,
     lists: lists,
     options: options,
     biscuit: biscuit,
     resident_path: ~p"/o/#{organisation.short_name}/residents/#{biscuit.id}",
     path: ~p"/o/#{organisation.short_name}/residents/#{biscuit.id}/journal",
     conn: sign_in(context.conn, member)}
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp submit(view, conn, selector, fields) do
    {:ok, view, _html} =
      view |> form(selector, fields) |> render_submit() |> follow_redirect(conn)

    {view, render_async(view)}
  end

  defp entries(context) do
    {:ok, entries} = Journal.entries(context.biscuit.id, context.options)
    entries
  end

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    assert {:error, {:redirect, %{to: "/"}}} =
             build_conn() |> sign_in(outsider) |> live(context.path)

    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.path)

    missing = ~p"/o/#{context.organisation.short_name}/residents/#{Ash.UUID.generate()}/journal"
    assert {:error, {:redirect, %{to: to}}} = live(context.conn, missing)
    assert to == ~p"/o/#{context.organisation.short_name}/residents"
  end

  describe "a new entry" do
    test "has words, the member who wrote it, and the time in the zone of the organisation",
         context do
      {view, html} = open(context.conn, context.path)
      assert html =~ "The journal has no entry yet."

      {view, html} =
        submit(view, context.conn, "#entry",
          entry: %{kind: "behaviour", note: "Popcorning at floor time."}
        )

      assert html =~ "Behaviour"
      assert html =~ "Popcorning at floor time."
      assert html =~ to_string(context.member.email)

      [entry] = entries(context)

      local =
        RescordWeb.JournalWords.time(
          Rescord.Accounts.local_time(context.organisation, entry.happened_at)
        )

      assert has_element?(view, "article time", local)
    end

    test "shows the fields of the kind that the member chooses", context do
      {view, _html} = open(context.conn, context.path)

      refute has_element?(view, "#entry [name='entry[value]']")

      view |> form("#entry", entry: %{kind: "measurement"}) |> render_change()
      assert has_element?(view, "#entry [name='entry[measure_kind_id]']")
      assert has_element?(view, "#entry [name='entry[value]']")
      refute has_element?(view, "#entry [name='entry[medication]']")

      view |> form("#entry", entry: %{kind: "prescription"}) |> render_change()
      assert has_element?(view, "#entry [name='entry[medication]']")
      assert has_element?(view, "#entry [name='entry[route]']")
      refute has_element?(view, "#entry [name='entry[value]']")
    end

    test "records a weight, and the page of the resident shows the newest one", context do
      {view, _html} = open(context.conn, context.path)
      view |> form("#entry", entry: %{kind: "measurement"}) |> render_change()

      {_view, html} =
        submit(view, context.conn, "#entry",
          entry: %{
            kind: "measurement",
            measure_kind_id: context.lists.measure_kind.weight,
            value: "1095",
            unit_id: context.lists.unit.g
          }
        )

      assert html =~ "Weight: 1,095 g"

      {_view, html} = open(context.conn, context.resident_path)
      assert html =~ "1,095 g,"
      refute html =~ "No measurement is recorded."
    end

    test "says what is wrong, and keeps what the member typed", context do
      {view, _html} = open(context.conn, context.path)
      view |> form("#entry", entry: %{kind: "vaccination"}) |> render_change()

      html =
        view
        |> form("#entry",
          entry: %{kind: "vaccination", vaccine: "", note: "Given in the left leg."}
        )
        |> render_submit()

      assert has_element?(view, "main p[role=alert]", "Vaccine is required")
      assert html =~ "Given in the left leg."
      assert entries(context) == []

      tomorrow =
        context.organisation |> Rescord.Accounts.today() |> Date.add(1) |> Date.to_iso8601()

      view
      |> form("#entry", entry: %{kind: "general", note: "Tomorrow.", at: tomorrow <> "T08:00"})
      |> render_submit()

      assert has_element?(view, "main p[role=alert]", "The time cannot be after now")
      assert entries(context) == []
    end
  end

  describe "the medical history" do
    test "has the entries of a medical kind only", context do
      Journal.write_entry!(
        %{resident_id: context.biscuit.id, kind: :general, note: "Ate well."},
        context.options
      )

      Journal.write_entry!(
        %{resident_id: context.biscuit.id, kind: :vaccination, vaccine: "A sample vaccine"},
        context.options
      )

      {view, html} = open(context.conn, context.path)
      assert html =~ "Ate well."
      assert html =~ "Vaccine: A sample vaccine"

      html = view |> element("a", "Show the medical history") |> render_click()
      refute html =~ "Ate well."
      assert html =~ "Vaccine: A sample vaccine"
      assert html =~ "The medical history"
    end
  end

  describe "an entry on the page" do
    setup context do
      entry =
        Journal.write_entry!(
          %{resident_id: context.biscuit.id, kind: :examination, note: "Mild chest sounds."},
          context.options
        )

      {:ok, entry: entry}
    end

    test "has a form to correct it for its author and an administrator, and not for another member",
         context do
      {view, _html} = open(context.conn, context.path)
      assert has_element?(view, "#correct-#{context.entry.id}")

      conn = build_conn() |> sign_in(context.other)
      {view, _html} = open(conn, context.path)
      refute has_element?(view, "#correct-#{context.entry.id}")

      # An event that the page did not offer is refused.
      render_submit(view, "correct", %{
        "entry_id" => context.entry.id,
        "entry" => %{"note" => "No."}
      })

      assert has_element?(view, "main p[role=alert]")
      assert [%{note: "Mild chest sounds."}] = entries(context)

      conn = build_conn() |> sign_in(context.administrator)
      {view, _html} = open(conn, context.path)

      {_view, html} =
        submit(view, conn, "#correct-#{context.entry.id}",
          entry: %{note: "Mild chest sounds on the left."}
        )

      assert html =~ "Mild chest sounds on the left."
      assert [%{author_id: author}] = entries(context)
      assert author == context.member.id
    end

    test "gets an addendum from another member", context do
      conn = build_conn() |> sign_in(context.other)
      {view, _html} = open(conn, context.path)

      {_view, html} =
        submit(view, conn, "#add-#{context.entry.id}",
          entry: %{note: "Clear on the second check."}
        )

      assert html =~ "Clear on the second check."
      assert html =~ "Adds to the entry of"
      assert html =~ to_string(context.other.email)

      assert [addendum, _first] = entries(context)
      assert addendum.follows.id == context.entry.id
      assert addendum.kind == :examination
    end
  end
end
