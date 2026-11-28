defmodule RescordWeb.ReportPagesTest do
  @moduledoc """
  Holds the page of the reports and the downloads (ADR 0076): the forms and
  the links, each PDF with its headers and its name, a day that is not
  right, and the answer for a person who may not read the organisation. It
  holds the paper too (ADR 0093): the control of the page, and the paper of
  an address.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures

  alias Rescord.Accounts

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, member} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    biscuit = resident!(lists, actor: member, tenant: organisation)
    today = Accounts.today(organisation)

    {:ok,
     root: root,
     organisation: organisation,
     member: member,
     biscuit: biscuit,
     home: "/o/#{organisation.short_name}",
     today: Date.to_iso8601(today),
     conn: sign_in(build_conn(), member)}
  end

  defp pdf(conn, name) do
    assert "%PDF-" <> _rest = response(conn, 200)
    assert response_content_type(conn, :pdf) == "application/pdf"
    assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="#{name}")]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    conn.resp_body
  end

  test "the page has a form or a link for each report, and the menu names it", context do
    %{conn: conn, home: home, today: today} = context
    {:ok, view, _html} = live(conn, "#{home}/reports")

    assert has_element?(view, "h1", "Reports")
    assert has_element?(view, ~s(#site-menu a[href="#{home}/reports"][aria-current="true"]))

    assert has_element?(view, ~s(form#register[action="#{home}/reports/register.pdf"]))
    assert has_element?(view, ~s(input#register-on[name="on"][value="#{today}"][max="#{today}"]))
    assert has_element?(view, ~s(label[for="register-on"]), "In care on")

    assert has_element?(view, ~s(form#movements[action="#{home}/reports/movements.pdf"]))
    assert has_element?(view, ~s(input#movements-from[name="from"]))
    assert has_element?(view, ~s(input#movements-to[name="to"][value="#{today}"]))
    assert has_element?(view, "#movements-periods a", "Last month")
    assert has_element?(view, "#movements-periods a", "This year so far")

    assert has_element?(view, ~s(form#task-sheet[action="#{home}/reports/tasks.pdf"]))
    assert has_element?(view, ~s(a#stock[href="#{home}/reports/stock.pdf?paper=a4"]))
    assert has_element?(view, ~s(a#housing[href="#{home}/reports/housing.pdf?paper=a4"]))

    assert has_element?(view, ~s(form#expenses[action="#{home}/reports/expenses.pdf"]))
    assert has_element?(view, ~s(input#expenses-from[name="from"]))
    assert has_element?(view, ~s(input#expenses-to[name="to"][value="#{today}"]))
    assert has_element?(view, "#expenses-periods a", "Last year")
    assert has_element?(view, ~s(a[href="#{home}/residents"]), "Choose a resident")

    # No form of the page has a method other than GET, and none speaks to
    # the page itself.
    refute has_element?(view, "main form[method=post]")
    refute has_element?(view, "main form[phx-submit]")
  end

  test "the page chooses the paper of each of its reports", context do
    %{conn: conn, home: home} = context
    {:ok, view, _html} = live(conn, "#{home}/reports")

    # The paper of the organisation is chosen at first, and each form and
    # each link sends it.
    assert has_element?(view, ~s(form#paper[action="#{home}/reports"]))
    assert has_element?(view, ~s(label[for="paper-size"]), "Paper")
    assert has_element?(view, ~s(select#paper-size[name="paper"] option[value="a4"][selected]))
    assert has_element?(view, ~s(select#paper-size option[value="us_letter"]), "US Letter")
    assert has_element?(view, "form#paper noscript button", "Use this paper")

    for form <- ~w(register movements task-sheet expenses) do
      assert has_element?(view, ~s(form##{form} input[type="hidden"][name="paper"][value="a4"]))
    end

    assert has_element?(view, ~s(#movements-periods a[href*="paper=a4"]), "Last month")
    assert has_element?(view, ~s(#expenses-periods a[href*="paper=a4"]), "Last year")

    # The other paper goes into the address, and then into each form and link.
    view |> element("form#paper") |> render_change(%{"paper" => "us_letter"})
    assert_patch(view, "#{home}/reports?paper=us_letter")

    assert has_element?(view, ~s(select#paper-size option[value="us_letter"][selected]))
    assert has_element?(view, "main p", "Each report of this page is on US Letter paper.")

    for form <- ~w(register movements task-sheet expenses) do
      assert has_element?(
               view,
               ~s(form##{form} input[type="hidden"][name="paper"][value="us_letter"])
             )
    end

    assert has_element?(view, ~s(a#stock[href="#{home}/reports/stock.pdf?paper=us_letter"]))
    assert has_element?(view, ~s(a#housing[href="#{home}/reports/housing.pdf?paper=us_letter"]))
    assert has_element?(view, ~s(#movements-periods a[href*="paper=us_letter"]), "Last month")

    # A paper that Rescord does not have changes nothing, in an event and
    # in the address.
    view |> element("form#paper") |> render_change(%{"paper" => "a3"})
    assert has_element?(view, ~s(select#paper-size option[value="us_letter"][selected]))

    {:ok, view, _html} = live(conn, "#{home}/reports?paper=a3")
    assert has_element?(view, ~s(select#paper-size option[value="a4"][selected]))

    # The paper of the organisation is the one that the page chooses first.
    {:ok, _organisation} =
      Accounts.set_organisation_paper_size(context.organisation, :us_letter, actor: context.root)

    {:ok, view, _html} = live(conn, "#{home}/reports")
    assert has_element?(view, ~s(select#paper-size option[value="us_letter"][selected]))
    assert has_element?(view, ~s(a#stock[href="#{home}/reports/stock.pdf?paper=us_letter"]))
  end

  test "the pages of the records link to their reports", context do
    %{conn: conn, home: home, biscuit: biscuit} = context

    {:ok, view, _html} = live(conn, "#{home}/residents/#{biscuit.id}")
    assert has_element?(view, "#documents h2", "On paper")

    assert has_element?(
             view,
             ~s(form#record[action="#{home}/residents/#{biscuit.id}/record.pdf"])
           )

    assert has_element?(view, ~s(select#record-journal[name="journal"] option[value="all"]))
    assert has_element?(view, ~s(input#record-photos[type="checkbox"][name="photos"]))

    # The record and the cage card share the control of the paper, so the
    # card is a second button of the form, with an address of its own.
    assert has_element?(view, ~s(select#record-paper[name="paper"] option[value="a4"][selected]))
    assert has_element?(view, ~s(select#record-paper option[value="us_letter"]), "US Letter")

    assert has_element?(
             view,
             ~s(form#record button#cage-card[type="submit"][formaction="#{home}/residents/#{biscuit.id}/card.pdf"])
           )

    {:ok, view, _html} = live(conn, "#{home}/residents")
    assert has_element?(view, ~s(a#register-report[href="#{home}/reports/register.pdf"]))

    {:ok, view, _html} = live(conn, "#{home}/tasks")

    assert has_element?(
             view,
             ~s(a#task-sheet[href="#{home}/reports/tasks.pdf?on=#{context.today}"])
           )

    {:ok, view, _html} = live(conn, "#{home}/inventory")
    assert has_element?(view, ~s(a#stock-report[href="#{home}/reports/stock.pdf"]))

    {:ok, view, _html} = live(conn, "#{home}/housing")
    assert has_element?(view, ~s(a#housing-report[href="#{home}/reports/housing.pdf"]))
  end

  test "each path sends its PDF, with a name for the file", context do
    %{conn: conn, home: home, today: today, biscuit: biscuit} = context

    body = conn |> get("#{home}/reports/register.pdf") |> pdf("register-#{today}.pdf")
    assert body =~ "Register of residents, Wattle Creek"

    conn |> get("#{home}/reports/register.pdf", %{"on" => ""}) |> pdf("register-#{today}.pdf")

    conn
    |> get("#{home}/reports/register.pdf", %{"on" => "2026-01-31"})
    |> pdf("register-2026-01-31.pdf")

    conn
    |> get("#{home}/reports/movements.pdf", %{"from" => "2026-01-01", "to" => "2026-01-31"})
    |> pdf("movements-2026-01-01-to-2026-01-31.pdf")

    conn |> get("#{home}/reports/tasks.pdf", %{"on" => today}) |> pdf("tasks-#{today}.pdf")
    conn |> get("#{home}/reports/stock.pdf") |> pdf("stock-#{today}.pdf")
    conn |> get("#{home}/reports/housing.pdf") |> pdf("housing-#{today}.pdf")

    body =
      conn
      |> get("#{home}/reports/expenses.pdf", %{"from" => "2026-01-01", "to" => "2026-01-31"})
      |> pdf("expenses-2026-01-01-to-2026-01-31.pdf")

    assert body =~ "Expenses, Wattle Creek"

    body =
      conn
      |> get("#{home}/residents/#{biscuit.id}/record.pdf", %{
        "journal" => "all",
        "photos" => "true"
      })
      |> pdf("biscuit-record-#{today}.pdf")

    assert body =~ "Record of Biscuit, Wattle Creek"
    assert body =~ "/Title(Journal)"

    body =
      conn
      |> get("#{home}/residents/#{biscuit.id}/record.pdf")
      |> pdf("biscuit-record-#{today}.pdf")

    assert body =~ "/Title(Medical history)"

    conn
    |> get("#{home}/residents/#{biscuit.id}/card.pdf")
    |> pdf("biscuit-cage-card-#{today}.pdf")
  end

  test "a path sends its PDF on the paper of the address, or on the one of the organisation",
       context do
    %{conn: conn, home: home, today: today, biscuit: biscuit} = context
    stock = "stock-#{today}.pdf"
    a4 = "/MediaBox[0 0 595."
    letter = "/MediaBox[0 0 612 792]"

    assert conn |> get("#{home}/reports/stock.pdf") |> pdf(stock) =~ a4
    assert conn |> get("#{home}/reports/stock.pdf", %{"paper" => "a4"}) |> pdf(stock) =~ a4

    assert conn |> get("#{home}/reports/stock.pdf", %{"paper" => "us_letter"}) |> pdf(stock) =~
             letter

    # A value that names no paper is the same as none.
    for other <- ["a3", "", "US Letter"] do
      assert conn |> get("#{home}/reports/stock.pdf", %{"paper" => other}) |> pdf(stock) =~ a4
    end

    assert conn |> get("#{home}/reports/stock.pdf?paper[]=a4") |> pdf(stock) =~ a4

    # Each path takes the paper. The cage card has it on its side.
    for {path, more} <- [
          {"reports/register.pdf", %{}},
          {"reports/movements.pdf", %{"from" => "2026-01-01", "to" => "2026-01-31"}},
          {"reports/tasks.pdf", %{}},
          {"reports/housing.pdf", %{}},
          {"reports/expenses.pdf", %{"from" => "2026-01-01", "to" => "2026-01-31"}},
          {"residents/#{biscuit.id}/record.pdf", %{"journal" => "none"}},
          {"residents/#{biscuit.id}/card.pdf", %{"journal" => "medical"}}
        ] do
      conn = get(conn, "#{home}/#{path}", Map.put(more, "paper", "us_letter"))
      assert response(conn, 200) =~ ~r/\/MediaBox\[0 0 (612 792|792 612)\]/, path
    end

    body =
      conn
      |> get("#{home}/residents/#{biscuit.id}/card.pdf", %{"paper" => "us_letter"})
      |> pdf("biscuit-cage-card-#{today}.pdf")

    assert body =~ "/MediaBox[0 0 792 612]"

    # With no paper in the address, the paper is the one of the organisation.
    {:ok, _organisation} =
      Accounts.set_organisation_paper_size(context.organisation, :us_letter, actor: context.root)

    assert conn |> get("#{home}/reports/stock.pdf") |> pdf(stock) =~ letter
    assert conn |> get("#{home}/reports/stock.pdf", %{"paper" => "a4"}) |> pdf(stock) =~ a4
  end

  test "a day that is not right goes back to the page with words", context do
    %{conn: conn, home: home, today: today} = context
    tomorrow = today |> Date.from_iso8601!() |> Date.add(1) |> Date.to_iso8601()

    for {path, params, words} <- [
          {"register.pdf", %{"on" => "soon"}, "The date is not a date."},
          {"register.pdf", %{"on" => tomorrow}, "The day is after today."},
          {"tasks.pdf", %{"on" => "31/01/2026"}, "The date is not a date."},
          {"movements.pdf", %{}, "Give the first day and the last day."},
          {"movements.pdf", %{"from" => today}, "Give the first day and the last day."},
          {"movements.pdf", %{"from" => today, "to" => "2026-01-01"},
           "The last day is before the first day."},
          {"movements.pdf", %{"from" => today, "to" => tomorrow}, "The last day is after today."},
          {"expenses.pdf", %{"to" => today}, "Give the first day and the last day."},
          {"expenses.pdf", %{"from" => today, "to" => "2026-01-01"},
           "The last day is before the first day."}
        ] do
      conn = get(conn, "#{home}/reports/#{path}", params)
      assert redirected_to(conn) == "#{home}/reports"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == words
    end
  end

  test "a person who cannot read the record gets no such page", context do
    %{conn: conn, home: home, biscuit: biscuit} = context

    # No resident with this id, and an id that is not one.
    assert conn
           |> get("#{home}/residents/#{Ash.UUID.generate()}/record.pdf")
           |> html_response(404)

    assert conn |> get("#{home}/residents/biscuit/card.pdf") |> html_response(404)

    # A person with no session.
    assert build_conn() |> get("#{home}/reports/stock.pdf") |> html_response(404)

    # A person of another refuge, for this refuge and for a resident of it
    # under the name of their own.
    other = organisation!(context.root, "Banksia Rise")
    {_, stranger} = member!(other, :administrator, context.root)
    conn = sign_in(build_conn(), stranger)

    assert conn |> get("#{home}/reports/register.pdf") |> html_response(404)
    assert conn |> get("#{home}/residents/#{biscuit.id}/record.pdf") |> html_response(404)

    assert conn
           |> get("/o/#{other.short_name}/residents/#{biscuit.id}/record.pdf")
           |> html_response(404)

    assert conn |> get("/o/#{other.short_name}/reports/stock.pdf") |> response(200)
  end

  test "a person who made too many reports reads that they must wait", context do
    %{conn: conn, home: home} = context

    for _number <- 1..30 do
      assert {:allow, _count} =
               Rescord.RateLimit.hit("reports/person/#{context.member.id}", :timer.minutes(1), 30)
    end

    conn = get(conn, "#{home}/reports/stock.pdf")
    assert response(conn, 429) =~ "Wait a minute"
    assert get_resp_header(conn, "retry-after") == ["60"]
  end
end
