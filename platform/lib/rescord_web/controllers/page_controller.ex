defmodule RescordWeb.PageController do
  use RescordWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
