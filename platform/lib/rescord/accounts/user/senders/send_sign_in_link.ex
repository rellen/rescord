defmodule Rescord.Accounts.User.Senders.SendSignInLink do
  @moduledoc """
  Sends the email with a sign-in link.

  AshAuthentication calls this with the user and the token, inside the task
  of the request (ADR 0019). It is not called for an address that Rescord
  does not know.

  The core cannot name the web layer (ADR 0009), which knows the address of
  the page. The configuration names the function that builds the link:
  `config :rescord, :sign_in_link_url, {module, function}`.
  """

  use AshAuthentication.Sender

  import Swoosh.Email

  @impl true
  def send(user, token, _opts) do
    {module, function} = Application.fetch_env!(:rescord, :sign_in_link_url)
    url = apply(module, function, [token])

    new()
    |> from(Application.fetch_env!(:rescord, :mail_from))
    |> to(to_string(user.email))
    |> subject("Your sign-in link for Rescord")
    |> text_body("""
    Somebody asked for a link to sign in to Rescord with this address.

    Open this link to sign in. It works one time, for 15 minutes:

    #{url}

    If you did not ask for it, do nothing. Nobody can sign in without this link.
    """)
    |> Rescord.Mailer.deliver!()

    :ok
  end
end
