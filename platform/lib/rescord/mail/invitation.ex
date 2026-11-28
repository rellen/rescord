defmodule Rescord.Mail.Invitation do
  @moduledoc """
  The email of an invitation to an organisation: `invitation.mjml.eex`, and
  its text part.
  """

  use MjmlEEx,
    mjml_template: "invitation.mjml.eex",
    layout: Rescord.Mail.Layout,
    mode: :compile

  @doc "The text part."
  @spec text(map) :: String.t()
  def text(%{organisation: organisation, invited_by: invited_by, url: url, note: note}) do
    """
    #{invited_by} invited you to #{organisation} on Rescord.

    To sign in, open this page and type this email address:

    #{url}

    Rescord then sends you a link to sign in. You need no password.

    #{note}
    """
  end
end
