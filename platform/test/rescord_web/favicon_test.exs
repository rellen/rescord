defmodule RescordWeb.FaviconTest do
  @moduledoc """
  Holds the icon of the tab to the mark of the site bar (ADR 0058): each page
  links the three files, the endpoint serves them, and the favicon has the
  two values of the token `accent`.
  """

  use RescordWeb.ConnCase, async: true

  @static "priv/static"

  defp href(doc, selector) do
    doc |> LazyHTML.query(selector) |> LazyHTML.attribute("href")
  end

  test "a page links the favicon, the ICO and the icon of a home screen", %{conn: conn} do
    doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert href(doc, ~s(head link[rel="icon"][type="image/svg+xml"])) == ["/images/favicon.svg"]
    assert href(doc, ~s(head link[rel="icon"][sizes="32x32"])) == ["/favicon.ico"]
    assert href(doc, ~s(head link[rel="apple-touch-icon"])) == ["/images/apple-touch-icon.png"]
  end

  for {path, type} <- [
        {"/images/favicon.svg", "image/svg+xml"},
        {"/favicon.ico", "image/vnd.microsoft.icon"},
        {"/images/apple-touch-icon.png", "image/png"}
      ] do
    test "the endpoint serves #{path}", %{conn: conn} do
      conn = get(conn, unquote(path))

      assert response(conn, 200) == File.read!(Path.join(@static, unquote(path)))
      assert [unquote(type) <> _] = get_resp_header(conn, "content-type")
    end
  end

  test "the favicon has the lead colour of each scheme" do
    svg = File.read!(Path.join(@static, "images/favicon.svg"))
    tokens = File.read!("assets/css/layers/tokens.css")

    assert [_, light, dark] =
             Regex.run(~r/--accent:\s*light-dark\((#[0-9a-f]{6}),\s*(#[0-9a-f]{6})\)/, tokens)

    assert Regex.scan(~r/#[0-9a-f]{6}/, svg) == [[light], [dark]]
    assert svg =~ "@media (prefers-color-scheme: dark) { g { stroke: #{dark}; } }"
  end

  test "the ICO holds a PNG of 16, of 32 and of 48 pixels" do
    assert <<0::16, 1::little-16, 3::little-16, entries::binary-size(48), _::binary>> =
             ico = File.read!(Path.join(@static, "favicon.ico"))

    images =
      for <<width, height, 0, 0, 1::little-16, 32::little-16, bytes::little-32,
            offset::little-32 <- entries>> do
        assert <<0x89, "PNG\r\n", 0x1A, "\n", _::binary>> = binary_part(ico, offset, bytes)
        {width, height}
      end

    assert images == [{16, 16}, {32, 32}, {48, 48}]
  end
end
