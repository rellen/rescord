defmodule Rescord.Mail do
  @moduledoc """
  The emails of Rescord (ADR 0070): the sign-in link, the invitation to an
  organisation, and the test email of `bin/check`.

  Each function takes plain values and returns a `Swoosh.Email` with the
  sender of the settings, a subject, an HTML part and a text part. It
  delivers nothing: the caller gives the email to `Rescord.Mailer`.

  The HTML part is MJML with EEx (`mjml_eex`), in `lib/rescord/mail/`: a
  layout, and a template for each email. The build turns the MJML into HTML,
  and a send only fills in the values, which `Phoenix.HTML` escapes. The
  text part is written by hand in the module of the template, and says the
  same.

  This is a boundary of its own, because the module of a template calls
  `Phoenix.HTML`, which the core may not use (ADR 0009). It uses no other
  boundary.

  To add an email: write `<name>.mjml.eex` with the content of the card,
  a module as `Rescord.Mail.SignInLink` beside it, a function here, and an
  entry in `previews/0`. `Rescord.MailTest` then checks it.
  """

  use Boundary, top_level?: true, deps: []

  import Swoosh.Email

  alias Rescord.Mail.{Invitation, MailWorks, SignInLink}

  @doc """
  The email with a sign-in link. `url` is the address that signs the person
  in.
  """
  @spec sign_in_link(String.t(), String.t()) :: Swoosh.Email.t()
  def sign_in_link(to, url) do
    build(to, "Your sign-in link for Rescord", SignInLink, %{
      url: url,
      preview: "Open the link to sign in. It works one time, for 15 minutes.",
      note: "If you did not ask for it, do nothing. Nobody can sign in without this link."
    })
  end

  @doc """
  The email of an invitation to the organisation with the name
  `organisation`. `invited_by` is the address of the member who invited the
  person, or `nil`. `url` is the address of the page where a person asks
  for a sign-in link: the email has no token.
  """
  @spec invitation(String.t(), String.t(), String.t() | nil, String.t()) :: Swoosh.Email.t()
  def invitation(to, organisation, invited_by, url) do
    build(to, "You are invited to #{organisation} on Rescord", Invitation, %{
      url: url,
      organisation: organisation,
      invited_by: invited_by || "Somebody",
      preview: "Sign in with this email address. You need no password.",
      note: "If you did not expect this invitation, do nothing."
    })
  end

  @doc "The test email of `bin/check`: it says that the mail settings work."
  @spec mail_works(String.t()) :: Swoosh.Email.t()
  def mail_works(to) do
    build(to, "Rescord can send mail", MailWorks, %{
      preview: "This email comes from bin/check.",
      note: "An operator of this server asked for this email, to test its mail settings."
    })
  end

  @doc """
  Each email with example values, as `{name, email}`, for the page of a
  developer under `/dev/mail` and for the tests.
  """
  @spec previews() :: [{String.t(), Swoosh.Email.t()}]
  def previews do
    # As long as a real token, and with no shape that a scan for secrets knows.
    token = String.duplicate("example-token-", 9)

    [
      {"sign-in-link",
       sign_in_link("kim@example.org", "https://rescord.example.org/sign-in/link?token=#{token}")},
      {"invitation",
       invitation(
         "kim@example.org",
         "Wattle Creek Refuge",
         "sam@example.org",
         "https://rescord.example.org/sign-in"
       )},
      {"mail-works", mail_works("kim@example.org")}
    ]
  end

  defp build(to, subject, template, values) do
    assigns = Map.merge(values, %{to: to, subject: subject})

    new()
    |> from(Application.fetch_env!(:rescord, :mail_from))
    |> to(to)
    |> subject(subject)
    |> html_body(template.render(assigns))
    |> text_body(template.text(assigns))
  end
end
