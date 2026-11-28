defmodule RescordWeb.PrivacyNoticeController do
  @moduledoc """
  The privacy notices (ADR 0105, issue 31, call 14), which each person
  reads with no sign-in:

    * `/privacy/<notice id>` - the notice of one organisation. The id is a
      random id made only for the link, and never the id of the
      organisation, so the link shows no list of refuges. A person with the
      power `privacy` makes a new one on the privacy page, and the old link
      ends;
    * `/privacy` - the notice of the server, for the account itself.

  Rescord fills a template from the settings of privacy of the
  organisation and of the server. An organisation adds paragraphs of its
  own, and cannot take out the parts on rights. A notice with a blank that
  nobody filled says so, and shows no half of a notice.
  """

  use RescordWeb, :controller

  alias Rescord.Privacy

  def show(conn, %{"notice_id" => notice_id}) when is_binary(notice_id) do
    case Privacy.notice(notice_id) do
      {:ok, notice} ->
        render(conn, :show, Map.put(notice, :page_title, "Privacy notice"))

      :error ->
        conn |> put_status(:not_found) |> put_view(RescordWeb.ErrorHTML) |> render(:"404")
    end
  end

  def index(conn, _params) do
    render(conn, :index,
      server: Privacy.instance_settings(),
      page_title: "Privacy notice of the server"
    )
  end
end
