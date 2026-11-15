defmodule Rescord.Accounts.Changes.Invite do
  @moduledoc """
  Invites the person with the address of the argument `email`.

  Before the member is made, the change finds the user of the address, or
  makes one. After the transaction, it sends an email that names the
  organisation and says where to sign in. The email has no token.

  A fault of the email does not undo the invitation: the member exists, and
  the person can ask for a sign-in link. The fault goes to the log.
  """

  use Ash.Resource.Change

  import Swoosh.Email

  require Logger

  alias Rescord.Accounts
  alias Rescord.Accounts.{Organisation, User}

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      address = Ash.Changeset.get_argument(changeset, :email)
      user = find_or_make_user(address)
      Ash.Changeset.force_change_attribute(changeset, :user_id, user.id)
    end)
    |> Ash.Changeset.after_transaction(fn changeset, result ->
      with {:ok, _member} <- result do
        send_email(changeset, context.actor)
      end

      result
    end)
  end

  defp find_or_make_user(address) do
    case Accounts.user_by_email!(address, authorize?: false) do
      nil ->
        User
        |> Ash.Changeset.for_create(:for_invitation, %{email: address})
        |> Ash.create!(authorize?: false)

      user ->
        user
    end
  end

  defp send_email(changeset, inviter) do
    organisation = organisation(changeset.tenant)
    {module, function} = Application.fetch_env!(:rescord, :sign_in_page_url)
    address = changeset |> Ash.Changeset.get_argument(:email) |> to_string()

    new()
    |> from(Application.fetch_env!(:rescord, :mail_from))
    |> to(address)
    |> subject("You are invited to #{organisation.name} on Rescord")
    |> text_body("""
    #{inviter_name(inviter)} invited you to #{organisation.name} on Rescord.

    To sign in, open this page and type this email address:

    #{apply(module, function, [])}

    Rescord then sends you a link to sign in. You need no password.
    """)
    |> Rescord.Mailer.deliver!()
  rescue
    error ->
      Logger.warning("The email of an invitation failed: #{inspect(error.__struct__)}")
  end

  defp inviter_name(%User{email: email}), do: to_string(email)
  defp inviter_name(_nobody), do: "Somebody"

  defp organisation(%Organisation{} = organisation), do: organisation

  defp organisation("org_" <> id) do
    Ash.get!(Organisation, id, authorize?: false)
  end
end
