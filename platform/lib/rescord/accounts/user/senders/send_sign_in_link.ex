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

  @impl true
  def send(user, token, _opts) do
    {module, function} = Application.fetch_env!(:rescord, :sign_in_link_url)
    url = apply(module, function, [token])

    user.email
    |> to_string()
    |> Rescord.Mail.sign_in_link(url)
    |> Rescord.Mailer.deliver!()

    :ok
  end
end
