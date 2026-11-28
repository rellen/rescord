defmodule Rescord.Mail.SignInLink do
  @moduledoc "The email with a sign-in link: `sign_in_link.mjml.eex`, and its text part."

  use MjmlEEx,
    mjml_template: "sign_in_link.mjml.eex",
    layout: Rescord.Mail.Layout,
    mode: :compile

  @doc "The text part."
  @spec text(map) :: String.t()
  def text(%{url: url, note: note}) do
    """
    Somebody asked for a link to sign in to Rescord with this address.

    Open this link to sign in. It works one time, for 15 minutes:

    #{url}

    #{note}
    """
  end
end
