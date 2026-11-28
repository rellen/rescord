defmodule Rescord.Accounts.Errors.InvitationNotSent do
  @moduledoc """
  The email of an invitation was not sent (ADR 0067, ADR 0077 E2). Oban
  runs the job again later. The error holds no address and no reason of the
  mail server: the log has the kind of that reason.

  It is a fault of the mail server, and not of the person, so its class is
  `:unknown`.
  """

  use Splode.Error, fields: [], class: :unknown

  @impl true
  def message(_error), do: "The email of an invitation was not sent"
end
