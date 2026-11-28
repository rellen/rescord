defmodule Rescord.Accounts.Actions.SendInvitation do
  @moduledoc """
  Sends the email of an invitation (ADR 0067): it names the organisation and
  says where to sign in. The email has no token: the person asks for a
  sign-in link, as each user does.

  The action listens to `:member_invited` in a job. The job is written in
  the transaction of the invitation, so it is there only when the member
  is, and it runs after the commit. A fault of the mail server returns an
  error, and Oban runs the job again later. The invitation stands in each
  case: the person can ask for a sign-in link with no email.

  The organisation is the tenant of the job, which is that of the
  invitation.
  """

  use Ash.Resource.Actions.Implementation

  require Logger

  alias Rescord.Accounts.Organisation

  @impl true
  def run(input, _opts, _context) do
    signal = Ash.ActionInput.get_argument(input, :signal)

    case input.tenant |> organisation() |> email(signal) |> Rescord.Mailer.deliver() do
      {:ok, _receipt} -> :ok
      {:error, reason} -> fault(reason)
    end
  rescue
    error -> fault(error)
  end

  # The log names the kind of the fault, and never the address.
  defp fault(reason) do
    Logger.warning("The email of an invitation failed: #{Rescord.Log.reason(reason)}")
    {:error, "the email of an invitation was not sent"}
  end

  defp email(organisation, signal) do
    {module, function} = Application.fetch_env!(:rescord, :sign_in_page_url)

    Rescord.Mail.invitation(
      to_string(signal.email),
      organisation.name,
      signal.invited_by && to_string(signal.invited_by),
      apply(module, function, [])
    )
  end

  defp organisation(%Organisation{} = organisation), do: organisation
  defp organisation("org_" <> id), do: Ash.get!(Organisation, id, authorize?: false)
end
