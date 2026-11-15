defmodule RescordWeb.PageController do
  use RescordWeb, :controller

  def home(conn, _params) do
    organisations =
      case conn.assigns.current_user do
        nil -> []
        user -> Rescord.Accounts.organisations_for(user)
      end

    render(conn, :home, organisations: organisations)
  end
end
