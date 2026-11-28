defmodule RescordWeb.ReportPagesTest do
  @moduledoc """
  Holds the page of the reports and the downloads (ADR 0076): the forms and
  the links, each PDF with its headers and its name, a day that is not
  right, and the answer for a person who may not read the organisation. It
  holds the paper too (ADR 0093): the control of the page, and the paper of
  an address. The tests of the page find what a person finds (ADR 0107).

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [element: 2, render_change: 2]
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

  # A part of the page, by its heading.
  defp part(name), do: main() |> region(name)

  # Where the form of a part sends, and the name and the value of one of its fields.
  defp sends(session, part, label) do
    field = part |> field(label)

    {attribute(session, part |> form(nil), "action"), attribute(session, field, "name"),
     value(session, field)}
  end

  @forms ["Register of residents", "Arrivals and departures", "Tasks of a day", "Expenses"]

  # The paper that each form of a report sends, in a field that no person sees.
  defp papers(session) do
    for name <- @forms do
      session
      |> one(part(name) |> form(nil))
      |> LazyHTML.query(~s(input[type="hidden"][name="paper"]))
      |> LazyHTML.attribute("value")
    end
  end

  test "the page has a form or a link for each report, and the menu names it", context do
    %{conn: conn, home: home, today: today} = context

    session =
      conn
      |> visit("#{home}/reports")
      |> assert_has(main() |> heading(level: 1), text: "Reports")

    assert attribute(session, navigation("Site") |> link("Reports"), "aria-current") == "true"

    register = part("Register of residents")
    assert sends(session, register, "In care on") == {"#{home}/reports/register.pdf", "on", today}
    assert attribute(session, register |> field("In care on"), "max") == today

    movements = part("Arrivals and departures")
    movements_pdf = "#{home}/reports/movements.pdf"
    assert {^movements_pdf, "from", _} = sends(session, movements, "From")
    assert sends(session, movements, "To") == {"#{home}/reports/movements.pdf", "to", today}
    assert has?(session, movements |> link("Last month"))
    assert has?(session, movements |> link("This year so far"))

    assert sends(session, part("Tasks of a day"), "Day") ==
             {"#{home}/reports/tasks.pdf", "on", today}

    assert href(session, part("Stock") |> link("Make the stock report")) ==
             "#{home}/reports/stock.pdf?paper=a4"

    assert href(session, part("Housing") |> link("Make the housing report")) ==
             "#{home}/reports/housing.pdf?paper=a4"

    expenses = part("Expenses")
    expenses_pdf = "#{home}/reports/expenses.pdf"
    assert {^expenses_pdf, "from", _} = sends(session, expenses, "From")
    assert sends(session, expenses, "To") == {"#{home}/reports/expenses.pdf", "to", today}
    assert has?(session, expenses |> link("Last year"))
    assert href(session, part("One resident") |> link("Choose a resident")) == "#{home}/residents"

    # No form of the page has a method other than GET, and none speaks to
    # the page itself.
    session
    |> refute_has("main form[method=post]")
    |> refute_has("main form[phx-submit]")
  end

  test "the page chooses the paper of each of its reports", context do
    %{conn: conn, home: home} = context
    paper = part("Paper")

    # The paper of the organisation is chosen at first, and each form and
    # each link sends it.
    session = visit(conn, "#{home}/reports")
    assert attribute(session, paper |> form(nil), "action") == "#{home}/reports"
    assert value(session, paper |> field("Paper")) == "A4"
    assert_has(session, paper |> field("Paper"), text: "US Letter")
    assert_has(session, paper |> button("Use this paper"))
    assert papers(session) == [["a4"], ["a4"], ["a4"], ["a4"]]
    assert href(session, part("Arrivals and departures") |> link("Last month")) =~ "paper=a4"
    assert href(session, part("Expenses") |> link("Last year")) =~ "paper=a4"

    # The other paper goes into the address, and then into each form and link.
    session =
      session
      |> select("Paper", option: "US Letter")
      |> assert_path("#{home}/reports", query_params: %{"paper" => "us_letter"})
      |> assert_has(paper, text: "Each report of this page is on US Letter paper.")

    assert value(session, paper |> field("Paper")) == "US Letter"
    assert papers(session) == [["us_letter"], ["us_letter"], ["us_letter"], ["us_letter"]]

    assert href(session, part("Stock") |> link("Make the stock report")) ==
             "#{home}/reports/stock.pdf?paper=us_letter"

    assert href(session, part("Housing") |> link("Make the housing report")) ==
             "#{home}/reports/housing.pdf?paper=us_letter"

    assert href(session, part("Arrivals and departures") |> link("Last month")) =~
             "paper=us_letter"

    # A paper that Rescord does not have changes nothing, in an event and
    # in the address.
    session =
      unwrap(session, &(&1 |> element("form#paper") |> render_change(%{"paper" => "a3"})))

    assert value(session, paper |> field("Paper")) == "US Letter"
    assert conn |> visit("#{home}/reports?paper=a3") |> value(paper |> field("Paper")) == "A4"

    # The paper of the organisation is the one that the page chooses first.
    {:ok, _organisation} =
      Accounts.set_organisation_paper_size(context.organisation, :us_letter, actor: context.root)

    session = visit(conn, "#{home}/reports")
    assert value(session, paper |> field("Paper")) == "US Letter"

    assert href(session, part("Stock") |> link("Make the stock report")) ==
             "#{home}/reports/stock.pdf?paper=us_letter"
  end

  test "the pages of the records link to their reports", context do
    %{conn: conn, home: home, biscuit: biscuit} = context
    record = "#{home}/residents/#{biscuit.id}/record.pdf"

    session = visit(conn, "#{home}/residents/#{biscuit.id}")
    documents = part("On paper")

    assert sends(session, documents, "The record holds") ==
             {record, "journal", "Its medical history"}

    assert_has(session, documents |> field("The record holds"), text: "Its whole journal")
    assert sends(session, documents, "With its photos") == {record, "photos", "true"}

    # The record and the cage card share the control of the paper, so the
    # card is a second button of the form, with an address of its own.
    assert sends(session, documents, "Paper") == {record, "paper", "A4"}
    assert_has(session, documents |> field("Paper"), text: "US Letter")
    card = documents |> form(nil) |> button("Make the cage card (PDF)")
    assert attribute(session, card, "type") == "submit"
    assert attribute(session, card, "formaction") == "#{home}/residents/#{biscuit.id}/card.pdf"

    for {page, words, report} <- [
          {"residents", "Register (PDF)", "reports/register.pdf"},
          {"tasks", "Sheet (PDF)", "reports/tasks.pdf?on=#{context.today}"},
          {"inventory", "Stock report (PDF)", "reports/stock.pdf"},
          {"housing", "Housing report (PDF)", "reports/housing.pdf"}
        ] do
      assert conn |> visit("#{home}/#{page}") |> href(main() |> link(words)) ==
               "#{home}/#{report}"
    end
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
          {"register.pdf", %{"on" => "soon"}, "Give a date as a day, a month and a year."},
          {"register.pdf", %{"on" => tomorrow}, "The day is after today."},
          {"tasks.pdf", %{"on" => "31/01/2026"}, "Give a date as a day, a month and a year."},
          {"movements.pdf", %{}, "Give a day in From and a day in To."},
          {"movements.pdf", %{"from" => today}, "Give a day in From and a day in To."},
          {"movements.pdf", %{"from" => today, "to" => "2026-01-01"},
           "The last day is before the first day."},
          {"movements.pdf", %{"from" => today, "to" => tomorrow}, "The last day is after today."},
          {"expenses.pdf", %{"to" => today}, "Give a day in From and a day in To."},
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
