defmodule RescordWeb.PageControllerTest do
  use RescordWeb.ConnCase

  test "GET / renders the home page inside the layout's landmarks", %{conn: conn} do
    doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert doc |> LazyHTML.query("main#main h1") |> LazyHTML.text() =~ "Rescord"
    assert doc |> LazyHTML.query(~s(a[href="#main"])) |> Enum.count() == 1
    assert doc |> LazyHTML.query(~s(header nav[aria-label])) |> Enum.count() == 1
    assert doc |> LazyHTML.query("[class]") |> Enum.count() == 0
  end

  test "the site menu of a person who is signed in is a popover that a button opens", %{
    conn: conn
  } do
    user = Rescord.AccountsFixtures.user!()

    doc =
      conn
      |> Rescord.AccountsFixtures.sign_in(user)
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()

    # The button names the menu, and the menu is a popover (ADR 0061).
    assert doc |> LazyHTML.query(~s(nav > button[popovertarget="site-menu"])) |> Enum.count() == 1
    assert doc |> LazyHTML.query("nav > #site-menu[popover]") |> Enum.count() == 1
    assert doc |> LazyHTML.query("#site-menu span") |> LazyHTML.text() == to_string(user.email)
    assert doc |> LazyHTML.query(~s(#site-menu a[href="/sign-out"])) |> Enum.count() == 1
    # The page is in no part of an organisation, so the menu marks none.
    assert doc |> LazyHTML.query("#site-menu [aria-current]") |> Enum.count() == 0
  end

  test "a person who is not signed in has the link to sign in, and no menu", %{conn: conn} do
    doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert doc |> LazyHTML.query(~s(nav > a[href="/sign-in"])) |> Enum.count() == 1
    assert doc |> LazyHTML.query("[popover], [popovertarget]") |> Enum.count() == 0
  end

  describe "the site footer and the colophon (ADR 0090)" do
    test "each page has a footer with the way to the colophon, and a title of its own", %{
      conn: conn
    } do
      doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

      assert doc |> LazyHTML.query(~s(footer nav[aria-label] a[href="/colophon"])) |> Enum.count() ==
               1

      assert doc |> LazyHTML.query("title") |> LazyHTML.text() |> String.trim() ==
               "Home · Rescord"
    end

    test "the footer says the version to a person who is signed in, and to no other", %{
      conn: conn
    } do
      version = "Rescord #{Application.spec(:rescord, :vsn)}"

      visitor = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
      refute visitor |> LazyHTML.query("footer") |> LazyHTML.text() =~ version

      member =
        conn
        |> Rescord.AccountsFixtures.sign_in(Rescord.AccountsFixtures.user!())
        |> get(~p"/")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert member |> LazyHTML.query("footer") |> LazyHTML.text() =~ version
    end

    test "each person can read the colophon, with the statement about accessibility", %{
      conn: conn
    } do
      doc = conn |> get(~p"/colophon") |> html_response(200) |> LazyHTML.from_document()

      assert doc |> LazyHTML.query("main#main h1") |> LazyHTML.text() =~ "Colophon"

      assert doc |> LazyHTML.query("title") |> LazyHTML.text() |> String.trim() ==
               "Colophon · Rescord"

      assert doc
             |> LazyHTML.query("section[aria-labelledby=accessibility] h2#accessibility")
             |> Enum.count() == 1

      assert doc |> LazyHTML.query("#accessibility ~ p") |> LazyHTML.text() =~ "WCAG"
      assert doc |> LazyHTML.query("[class]") |> Enum.count() == 0
    end
  end
end
