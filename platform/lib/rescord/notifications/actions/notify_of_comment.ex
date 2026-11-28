defmodule Rescord.Notifications.Actions.NotifyOfComment do
  @moduledoc """
  The listener of `:commented`: a notification for each person who follows
  the record of the comment, but the writer (issue 29).

    * A person whom the writer told gets `:told`; each other follower gets
      `:comment`.
    * A person who is no member now gets none.
    * A person who cannot read the comment gets none: the listener reads it
      as that person. So the comment on an expense of one member tells
      nobody who cannot open the expense.

  It runs in the transaction of the comment, as of its tenant. It reads the
  followers and the comment with no policy: the comment was the decision,
  and the check of each person is the read as that person.
  """

  use Ash.Resource.Actions.Implementation

  alias Rescord.{Accounts, Comments}
  alias Rescord.Notifications.Notification

  @impl true
  def run(input, _opts, context) do
    signal = input.arguments.signal
    tenant = context.tenant

    with %Comments.Comment{} = comment <-
           Comments.comment_for_job(signal.comment_id, tenant: tenant) do
      told = MapSet.new(comment.told_ids)

      (Comments.followers_of(comment, tenant: tenant) ++ comment.told_ids)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == comment.author_id))
      |> Enum.filter(&reads?(&1, comment, tenant))
      |> Enum.each(fn user_id ->
        Ash.create!(
          Notification,
          %{
            user_id: user_id,
            comment_id: comment.id,
            kind: if(MapSet.member?(told, user_id), do: :told, else: :comment)
          },
          action: :make,
          tenant: tenant,
          authorize?: false
        )
      end)
    end

    :ok
  end

  defp reads?(user_id, comment, tenant) do
    with %Accounts.User{} = user <- Accounts.user_for_job(user_id),
         true <- Accounts.member_for_job(user_id, tenant),
         {:ok, %{}} <- Comments.comment(comment.id, actor: user, tenant: tenant) do
      true
    else
      _no -> false
    end
  end
end
