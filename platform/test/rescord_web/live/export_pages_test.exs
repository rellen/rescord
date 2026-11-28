defmodule RescordWeb.ExportPagesTest do
  @moduledoc """
  Holds the page of the export (ADR 0054) and its download: the form for a
  role with the power `export`, the words for one without it, the ZIP, and
  a refusal that goes back to the page.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Accounts

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    resident!(lists, actor: administrator, tenant: organisation)

    {:ok,
     organisation: organisation,
     administrator: administrator,
     member: member,
     path: ~p"/o/#{organisation.short_name}/export",
     today: Date.to_iso8601(Accounts.today(organisation))}
  end

  test "an administrator chooses a date, today at first, and downloads a ZIP", context do
    conn = sign_in(build_conn(), context.administrator)
    {:ok, view, _html} = live(conn, context.path)

    assert has_element?(view, "h1", "Export the data")
    assert has_element?(view, ~s(form#export[action="#{context.path}"][method="post"]))

    assert has_element?(
             view,
             ~s(input#export-on[type="date"][value="#{context.today}"][max="#{context.today}"])
           )

    assert has_element?(view, ~s(label[for="export-on"]), "Day")
    refute has_element?(view, "#no-export")

    conn = post(conn, context.path, %{"export" => %{"on" => context.today}})

    assert response(conn, 200)
    assert response_content_type(conn, :zip) =~ "application/zip"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="rescord-#{context.organisation.short_name}-#{context.today}.zip")
           ]

    assert {:ok, entries} = :zip.unzip(conn.resp_body, [:memory])

    assert Enum.any?(entries, fn {name, bytes} ->
             to_string(name) =~ "resident_names.csv" and bytes =~ "Biscuit"
           end)
  end

  test "a member without the power reads why, and a post goes back with words", context do
    conn = sign_in(build_conn(), context.member)
    {:ok, view, _html} = live(conn, context.path)

    assert has_element?(view, "#no-export", "Your role cannot export the data")
    refute has_element?(view, "form#export")

    conn = post(conn, context.path, %{"export" => %{"on" => context.today}})
    assert redirected_to(conn) == context.path
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Your role cannot export the data."
  end

  test "a date that is not a date, or after today, goes back with words", context do
    conn = sign_in(build_conn(), context.administrator)

    conn = post(conn, context.path, %{"export" => %{"on" => "soon"}})
    assert redirected_to(conn) == context.path

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Give a date as a day, a month and a year."

    tomorrow = context.today |> Date.from_iso8601!() |> Date.add(1) |> Date.to_iso8601()

    conn =
      post(sign_in(build_conn(), context.administrator), context.path, %{
        "export" => %{"on" => tomorrow}
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "The date is after today."
  end

  test "a person outside the organisation finds no export", context do
    conn = sign_in(build_conn(), user!())
    conn = post(conn, context.path, %{"export" => %{"on" => context.today}})
    assert response(conn, 404)
  end

  test "the page of the organisation links to the export", context do
    conn = sign_in(build_conn(), context.member)
    {:ok, view, _html} = live(conn, ~p"/o/#{context.organisation.short_name}")
    assert has_element?(view, ~s(a[href="#{context.path}"]), "Export the data")
  end
end
