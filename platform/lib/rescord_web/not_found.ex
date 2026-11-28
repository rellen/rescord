defmodule RescordWeb.NotFound do
  @moduledoc """
  A page that is not there for this person. A LiveView raises it in
  `mount/3`, and the person gets the page of an error 404, as for an
  address that Rescord does not know: the page says nothing of what it
  would have held, or that it exists for somebody else.

      unless Rescord.Ruby.available?(user, organisation), do: raise(RescordWeb.NotFound)
  """

  defexception message: "this page is not there for this person", plug_status: 404
end
