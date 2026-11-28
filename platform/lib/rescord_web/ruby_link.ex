defmodule RescordWeb.RubyLink do
  @moduledoc """
  Whether the person of a page can ask Ruby (ADR 0069), for the links to
  Ruby: in the site bar, in the menu, on the first page of the
  organisation and on the page of a record. A hook of the live session of
  an organisation: it assigns `ruby?` from `Rescord.Ruby.available?/2`,
  once for each page.

  Each page of an organisation passes `ruby={@ruby?}` to `Layouts.app`.
  Nobody else sees a link to Ruby, and for them the page of Ruby is a
  page that is not there.
  """

  alias Rescord.Ruby

  def on_mount(:check, _params, _session, socket) do
    %{current_user: user, organisation: organisation} = socket.assigns
    {:cont, Phoenix.Component.assign(socket, :ruby?, Ruby.available?(user, organisation))}
  end
end
