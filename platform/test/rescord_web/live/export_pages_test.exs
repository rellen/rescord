defmodule RescordWeb.ExportPagesTest do
  @moduledoc """
  Holds the page of the export (ADR 0054) and its download: the form for a
  role with the power `export`, the words for one without it, the ZIP, and
  a refusal that goes back to the page. The page is found as a person finds
  it (ADR 0107); the download is no page, so it stays a request.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

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
    download = main() |> region("Download")

    session =
      conn
      |> visit(context.path)
      |> assert_has(main() |> heading("Export the data", level: 1))
      # The form is a plain request, as the answer is a file and no page.
      |> assert_has(~s(form[action="#{context.path}"][method="post"]))
      |> assert_has(download |> button("Download the export"))
      |> refute_has(main(), text: "Your role cannot export the data")

    day = one(session, download |> field("Day"))
    assert value(session, download |> field("Day")) == context.today
    assert LazyHTML.attribute(day, "type") == ["date"]
    assert LazyHTML.attribute(day, "max") == [context.today]

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

    conn
    |> visit(context.path)
    |> assert_has(main(), text: "Your role cannot export the data")
    |> refute_has(main() |> region("Download"))
    |> refute_has(main() |> field("Day"))

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
    session =
      build_conn() |> sign_in(context.member) |> visit(~p"/o/#{context.organisation.short_name}")

    parts = main() |> navigation("The parts of Wattle Creek")
    assert href(session, parts |> link("Export the data")) == context.path
  end
end
