defmodule RescordWeb.PageControllerTest do
  use RescordWeb.ConnCase

  test "GET / renders the home page inside the layout's landmarks", %{conn: conn} do
    doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert doc |> LazyHTML.query("main#main h1") |> LazyHTML.text() =~ "Rescord"
    assert doc |> LazyHTML.query(~s(a[href="#main"])) |> Enum.count() == 1
    assert doc |> LazyHTML.query(~s(header nav[aria-label])) |> Enum.count() == 1
    assert doc |> LazyHTML.query("[class]") |> Enum.count() == 0
  end
end
