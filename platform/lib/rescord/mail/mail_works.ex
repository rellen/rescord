defmodule Rescord.Mail.MailWorks do
  @moduledoc "The test email of `bin/check`: `mail_works.mjml.eex`, and its text part."

  use MjmlEEx,
    mjml_template: "mail_works.mjml.eex",
    layout: Rescord.Mail.Layout,
    mode: :compile

  @doc "The text part."
  @spec text(map) :: String.t()
  def text(%{note: note}) do
    """
    This email comes from bin/check. Rescord can send the sign-in links and the invitations.

    #{note}
    """
  end
end
