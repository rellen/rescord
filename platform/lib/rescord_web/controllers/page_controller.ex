defmodule RescordWeb.PageController do
  use RescordWeb, :controller

  def home(conn, _params) do
    organisations =
      case conn.assigns.current_user do
        nil -> []
        user -> Rescord.Accounts.organisations_for(user)
      end

    render(conn, :home, organisations: organisations, page_title: "Home")
  end

  # The colophon (ADR 0090): what Rescord is built with, and its statement
  # about accessibility. Each person can read it, signed in or not. A
  # person who is signed in also sees the version of libvips (issue 37); a
  # visitor does not, as for the version of Rescord in the footer.
  def colophon(conn, _params) do
    libvips = conn.assigns[:current_user] && Rescord.Images.libvips_version()
    render(conn, :colophon, page_title: "Colophon", libvips: libvips)
  end
end
