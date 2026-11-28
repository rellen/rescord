defmodule RescordWeb.ErrorHTML do
  @moduledoc """
  The page of an error, for a request that asks for HTML (ADR 0090).

  The endpoint renders it for a request that no route takes and for a
  request that fails, and a controller renders `:"404"` for a file that the
  person cannot read. In each case the root layout is around it
  (`render_errors` in `config/config.exs`), so the page has a language, a
  title, the landmarks and a heading, as each other page.

  The page uses nothing that can fail a second time: no session, no person,
  no database. `words/1` gives the title and the advice of a status, and
  the root layout reads the title from it.
  """
  use RescordWeb, :html

  @doc """
  Renders the page of the status that the name of the template starts
  with: `"404.html"` is the page of the status 404.
  """
  def render(template, _assigns) do
    assigns = template |> status() |> words()

    ~H"""
    <Layouts.plain>
      <.header>
        {@title}
        <:subtitle>{@advice}</:subtitle>
      </.header>
      <p><a href={~p"/"}>Go to the first page of Rescord</a>.</p>
    </Layouts.plain>
    """
  end

  @doc "The title and the advice of the page of a status."
  def words(404) do
    %{
      title: "Rescord has no page at this address",
      advice: "The address can be wrong, or the page can be gone."
    }
  end

  def words(status) when status in 500..599 do
    %{
      title: "Something went wrong",
      advice: "Rescord could not show this page. Wait a minute, and then try again."
    }
  end

  def words(status) do
    %{title: phrase(status), advice: "Rescord could not do what the address asks."}
  end

  # The words of HTTP for a status, such as "Forbidden". Plug raises for a
  # number that it does not know.
  defp phrase(status) do
    Plug.Conn.Status.reason_phrase(status)
  rescue
    ArgumentError -> "Error #{status}"
  end

  # The status in the name of a template, such as `"404.html"` or `"404"`.
  defp status(template) do
    case Integer.parse(template) do
      {status, _rest} when status in 400..599 -> status
      _other -> 500
    end
  end
end
