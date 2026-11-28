defmodule RescordWeb.ConsistencyTest do
  @moduledoc """
  Holds each kind of page to the rules of "One way for each pattern of a
  page" in AGENTS.md (issue 35), so that a person who learnt one page knows
  the next one (WCAG 3.2.3 and 3.2.4):

    * no element asks with `data-confirm`, the dialog of the browser;
    * each danger button is the last button of a confirm step;
    * a breadcrumb is the one of `<.header>`, with a list, and there is one
      at most;
    * a page below a page of the menu has a breadcrumb;
    * each submit button of `main` is in the `<footer>` of its form, or in
      a row of a table or a list.

  The rules are about the markup that the server writes, so the test reads
  it, as the administrator, after the collections of Cinder have loaded.
  It needs no browser. `RescordWeb.PagesFixtures` makes the refuge and
  names its pages: a new page there is held here too. The test creates an
  organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures, only: [sign_in: 2]

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    refuge = RescordWeb.PagesFixtures.refuge!(tmp_dir, "consistency@wattle-creek.example.org")
    {:ok, refuge}
  end

  test "each page keeps the rules of one way for each pattern", context do
    conn = sign_in(build_conn(), context.administrator)

    problems =
      Enum.flat_map(context.pages, fn path ->
        path |> html(conn) |> LazyHTML.from_document() |> problems(path, context.home)
      end)

    assert problems == [], Enum.join(problems, "\n")
  end

  # The markup of a page, after a live page has connected and Cinder has
  # read its rows.
  defp html(path, conn) do
    response = get(conn, path)
    body = html_response(response, 200)

    if body =~ "data-phx-main" do
      {:ok, view, _html} = live(conn, path)
      render_async(view)
      render(view)
    else
      body
    end
  end

  defp problems(document, path, home) do
    [
      {count(document, "[data-confirm]") == 0, "asks with data-confirm"},
      {count(document, ~s([data-variant="danger"])) ==
         count(document, ~s(details[data-confirm-step] [data-variant="danger"])),
       "has a danger button outside a confirm step"},
      {count(document, ~s(nav[aria-label="Breadcrumb"])) ==
         count(document, ~s(nav[aria-label="Breadcrumb"] > ol)),
       "has a breadcrumb that is not the one of the header"},
      {count(document, ~s(nav[aria-label="Breadcrumb"])) <= 1, "has more than one breadcrumb"},
      {not below_the_menu?(path, home) or count(document, ~s(nav[aria-label="Breadcrumb"])) == 1,
       "is below a page of the menu and has no breadcrumb"},
      {loose_submits(document) == [],
       "has a submit button that is not in the footer of its form: " <>
         Enum.join(loose_submits(document), ", ")}
    ]
    |> Enum.reject(&elem(&1, 0))
    |> Enum.map(fn {_kept, words} -> "#{path} #{words}" end)
  end

  defp count(document, selector), do: document |> LazyHTML.query(selector) |> Enum.count()

  # The ids of the forms of `main` with a submit button outside their
  # footer. A form in a row of a table or a list has no footer.
  defp loose_submits(document) do
    in_rows =
      MapSet.new(
        LazyHTML.query(document, "main td form, main li form"),
        &LazyHTML.to_html/1
      )

    for form <- LazyHTML.query(document, "main form"),
        not MapSet.member?(in_rows, LazyHTML.to_html(form)),
        count(form, ~s(button[type="submit"])) !=
          count(form, ~s(footer button[type="submit"])) +
            count(form, ~s(noscript button[type="submit"])),
        do: form |> LazyHTML.attribute("id") |> List.first() || "a form with no id"
  end

  # A page of an organisation two steps or more below its first page, such
  # as `residents/<id>`: the menu has the first step.
  defp below_the_menu?(path, home) do
    case String.split(URI.parse(path).path, home <> "/", parts: 2) do
      ["", rest] -> rest |> String.split("/", trim: true) |> length() >= 2
      _other -> false
    end
  end
end
