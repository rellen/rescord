defmodule Rescord.Comments.Signals do
  @moduledoc """
  What the comments tell the other domains (ADR 0067).

    * `:commented` - a member wrote a comment. `Rescord.Notifications`
      listens in the transaction of the comment, and makes a notification
      for each person who follows its record. The signal holds the id of
      the comment and nothing of its words.

  `mix ash.signals` prints what emits each signal and what listens to it.
  """

  use Ash.Signals

  signals do
    signal :commented do
      description "A member wrote a comment on a record of the organisation"
      argument :comment_id, :uuid, allow_nil?: false
    end
  end
end
