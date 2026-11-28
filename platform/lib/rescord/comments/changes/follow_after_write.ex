defmodule Rescord.Comments.Changes.FollowAfterWrite do
  @moduledoc """
  After a comment is written, its writer and each person told follow its
  record (issue 29). A person who follows it already stays as they are.

  It writes in the transaction of the comment, with no policy: the write
  was the decision, and the people told are members (`Members`).
  """

  use Ash.Resource.Change

  alias Rescord.Comments.{Follow, Subject}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, comment ->
      fields = Map.new(Subject.columns(), &{&1, Map.get(comment, &1)})

      [comment.author_id | comment.told_ids]
      |> Enum.uniq()
      |> Enum.map(&Map.put(fields, :user_id, &1))
      |> Ash.bulk_create(Follow, :add,
        tenant: changeset.tenant,
        context: Rescord.Correlation.context(changeset),
        authorize?: false,
        upsert?: true,
        upsert_identity: :one_follow,
        upsert_fields: [:user_id],
        return_errors?: true,
        notify?: true
      )
      |> case do
        %Ash.BulkResult{status: :success} -> {:ok, comment}
        %Ash.BulkResult{errors: errors} -> {:error, errors}
      end
    end)
  end
end
