defmodule Rescord.Comments.Grants do
  @moduledoc """
  What a role can do with the comments of an organisation (ADR 0024 and
  issue 29).

  **Each role reads the comments of the records that it reads**: those of
  each resident, task and transfer, and those of an expense only where the
  person reads the expense, as `Rescord.Expenses.Grants` decides. The power
  `manage_expenses` reads the comments of each expense. Each role reads and
  ends its own follows.

  The power `comments` writes a comment, changes and deletes the person's
  own, and follows a record. A member and an administrator have it at
  first. The power `moderate_comments` deletes any comment, and each
  comment of one person at once. Only the administrators have it at first
  (ADR 0040).
  """

  @behaviour Rescord.Accounts.Grants

  import Ash.Expr, only: [expr: 1, actor: 1]

  alias Rescord.Comments.{Comment, Follow}

  @impl true
  def reads,
    do: [{Comment, :read, :readable}, {Follow, :read, :own}, {Follow, :unfollow, :own}]

  @impl true
  def powers do
    %{
      comments: [
        {Comment, :write, :all},
        {Comment, :revise, :own},
        {Comment, :delete, :own},
        {Follow, :follow, :all}
      ],
      moderate_comments: [{Comment, :delete, :all}, {Comment, :erase, :all}],
      manage_expenses: [{Comment, :read, :all}]
    }
  end

  @impl true
  def filter(Comment, :own), do: expr(author_id == ^actor(:id))

  def filter(Comment, :readable),
    do:
      expr(
        is_nil(expense_id) or
          exists(expense, author_id == ^actor(:id) or payer_id == ^actor(:id))
      )

  def filter(Follow, :own), do: expr(user_id == ^actor(:id))
  def filter(_resource, _scope), do: nil
end
