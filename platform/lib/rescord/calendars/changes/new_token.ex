defmodule Rescord.Calendars.Changes.NewToken do
  @moduledoc """
  Gives a new feed its owner and its token (ADR 0074).

  The owner is the member of the actor in the organisation: no input names
  the owner. A user who is not a member there, such as a root user who only
  looks, gets no feed.

  The change stores the hash of a new token, and puts the token itself in
  the metadata `:token` of the feed that the action returns. That is the
  one time that Rescord has the token.

  A member has at most `limit/0` feeds: each one is an address that reads
  the data of the organisation.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Accounts
  alias Rescord.Calendars.{Feed, Token}

  # The feeds that one member can have at one time.
  @limit 10

  @doc "The most feeds that one member can have."
  @spec limit() :: pos_integer
  def limit, do: @limit

  @impl true
  def change(changeset, _opts, %{actor: %Accounts.User{id: user_id}}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      internal = [
        tenant: changeset.tenant,
        context: Map.take(changeset.context, [:shared]),
        authorize?: false
      ]

      case Accounts.member_of_user(user_id, internal) do
        {:ok, %{id: member_id}} ->
          if count(member_id, internal) < @limit do
            give_token(changeset, member_id, user_id)
          else
            Ash.Changeset.add_error(changeset,
              field: :name,
              message: "cannot be added: you have #{@limit} feeds. Revoke one first"
            )
          end

        _not_a_member ->
          Ash.Changeset.add_error(changeset,
            field: :member_id,
            message: "is necessary: only a member of the organisation has a calendar feed"
          )
      end
    end)
  end

  # With no user the change does nothing, and the policy refuses the action.
  def change(changeset, _opts, _context), do: changeset

  defp count(member_id, internal) do
    Feed |> Ash.Query.filter(member_id == ^member_id) |> Ash.count!(internal)
  end

  defp give_token(changeset, member_id, user_id) do
    token = Token.new()

    changeset
    |> Ash.Changeset.force_change_attribute(:member_id, member_id)
    |> Ash.Changeset.force_change_attribute(:owner_id, user_id)
    |> Ash.Changeset.force_change_attribute(:token_hash, Token.hash(token))
    |> Ash.Changeset.after_action(fn _changeset, feed ->
      {:ok, Ash.Resource.put_metadata(feed, :token, token)}
    end)
  end
end
