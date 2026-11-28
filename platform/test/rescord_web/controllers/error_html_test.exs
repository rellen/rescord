defmodule RescordWeb.ErrorHTMLTest do
  @moduledoc """
  Holds the page of an error (ADR 0090): it is a page as each other one,
  with a language, a title, the landmarks and a heading, for a request that
  no route takes and for a file that a controller refuses.
  """

  use RescordWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  defp text(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "the page of a status has the landmarks, a heading and a way back" do
    doc = RescordWeb.ErrorHTML |> render_to_string("404", "html", []) |> LazyHTML.from_fragment()

    assert text(doc, "main#main h1") == "Rescord has no page at this address"
    assert count(doc, ~s(a[href="#main"])) == 1
    assert count(doc, "header nav[aria-label]") == 1
    assert count(doc, "footer nav[aria-label]") == 1
    assert count(doc, ~s(main a[href="/"])) == 1
  end

  test "a fault of the server and each other status have words of their own" do
    for {template, title} <- [
          {"500", "Something went wrong"},
          {"503", "Something went wrong"},
          {"403", "Forbidden"},
          {"499", "Error 499"}
        ] do
      doc =
        RescordWeb.ErrorHTML |> render_to_string(template, "html", []) |> LazyHTML.from_fragment()

      assert text(doc, "h1") == title
    end
  end

  test "an address with no page gets a whole document, with its title", %{conn: conn} do
    conn = get(conn, "/no-such-page")
    html = html_response(conn, 404)
    doc = LazyHTML.from_document(html)

    assert count(doc, ~s(html[lang="en"])) == 1
    assert text(doc, "title") == "Rescord has no page at this address · Rescord"
    assert count(doc, "main h1") == 1
    assert count(doc, ~s(link[rel="stylesheet"])) == 1
  end
end
