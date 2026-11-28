defmodule Rescord.Comments do
  @moduledoc """
  The comments of an organisation on its records, and who follows a record
  (issue 29, ADR 0106).

  A comment is plain text on one record: a resident, a task, a transfer or
  an expense. Each member who can read the record reads its comments: the
  grants hold that for the expenses, whose comments only the people who
  read the expense read (`Rescord.Comments.Grants`). `write/3` checks that
  the writer can read the record, and that each person told is a member.

  The writer and each person told follow the record from then on. The
  action emits `:commented` (`Rescord.Comments.Signals`), and
  `Rescord.Notifications` makes the notifications of the followers.

  A comment is deleted for real: the row goes, and its versions keep who
  and when with no word of it.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.Comments.{Comment, Follow, Subject}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true

    deps [
      Rescord,
      Rescord.Accounts,
      Rescord.Residents,
      Rescord.Tasks,
      Rescord.Expenses,
      Rescord.Transfers
    ]

    exports [
      Rescord.Comments.Subject,
      Rescord.Comments.Signals
    ]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Comment do
      define :comment, action: :read, get_by: [:id], not_found_error?: false
      define :write_comment, action: :write
      define :revise_comment, action: :revise, args: [:body]
      define :delete_comment, action: :delete
    end

    resource Follow do
      define :follow_record, action: :follow
      define :unfollow_record, action: :unfollow
    end
  end

  @doc """
  The comments of one record that the actor reads, the oldest first.
  `subject` is `{kind, id}` of `Rescord.Comments.Subject`.
  """
  @spec comments_on(Subject.t(), keyword) :: {:ok, [Comment.t()]} | {:error, term}
  def comments_on({kind, id} = _subject, opts) do
    column = Subject.column(kind)

    Comment
    |> Ash.Query.filter(^Ash.Expr.ref(column) == ^id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.read(opts)
  end

  @doc """
  Writes a comment on `subject` as the actor of `opts`, and tells each user
  of `told_ids`.
  """
  @spec write(Subject.t(), map, keyword) :: {:ok, Comment.t()} | {:error, term}
  def write({kind, id}, %{} = fields, opts) do
    fields
    |> Map.take([:body, :told_ids])
    |> Map.put(Subject.column(kind), id)
    |> write_comment(opts)
  end

  @doc """
  The people whom `comments` name, as their writer and as the members they
  told, read as the actor: `%{user_id => {email, :member | :former}}`.

  A member who left the organisation keeps their comments, and their name
  on them, with the mark `:former`, as Rob chose (28 November 2026). The
  comments are ones that the actor read, and each person that one names was
  a member when it was written, so the address is no news to the actor. A
  user who is gone from the server is not in the map: a page then says "a
  former member" with no address. The erasure of a person on request is a
  design of its own, which starts there.
  """
  @spec people([Comment.t()], keyword) :: %{Ecto.UUID.t() => {String.t(), :member | :former}}
  def people(comments, opts) do
    {:ok, members} = Rescord.Accounts.members([load: [:email]] ++ opts)
    current = Map.new(members, &{&1.user_id, {to_string(&1.email), :member}})

    named =
      comments
      |> Enum.flat_map(&[&1.author_id | &1.told_ids])
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(current, &1))

    named
    |> Rescord.Accounts.emails_of_users()
    |> Map.new(fn {id, email} -> {id, {email, :former}} end)
    |> Map.merge(current)
  end

  @doc "Whether the actor follows the record."
  @spec following?(Subject.t(), keyword) :: boolean
  def following?({kind, id}, opts) do
    case follow_of({kind, id}, opts) do
      {:ok, %Follow{}} -> true
      _none -> false
    end
  end

  @doc "The actor follows the record. Twice is the same as once."
  @spec follow(Subject.t(), keyword) :: {:ok, Follow.t()} | {:error, term}
  def follow({kind, id}, opts), do: follow_record(%{Subject.column(kind) => id}, opts)

  @doc "The actor stops following the record."
  @spec unfollow(Subject.t(), keyword) :: :ok | {:error, term}
  def unfollow(subject, opts) do
    case follow_of(subject, opts) do
      {:ok, %Follow{} = follow} -> unfollow_record(follow, opts)
      {:ok, nil} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp follow_of({kind, id}, opts) do
    column = Subject.column(kind)

    case Keyword.get(opts, :actor) do
      %{id: user_id} ->
        Follow
        |> Ash.Query.filter(^Ash.Expr.ref(column) == ^id and user_id == ^user_id)
        |> Ash.read_one(opts)

      _nobody ->
        {:ok, nil}
    end
  end

  @doc """
  The users who follow the record of a comment, for the notifications.
  Only `Rescord.Notifications` calls it, in the listener of `:commented`,
  which has no person to read as: it reads with no policy, and each
  notification is then checked as its person.
  """
  @spec followers_of(Comment.t(), keyword) :: [Ecto.UUID.t()]
  def followers_of(%Comment{} = comment, opts) do
    {kind, id} = Subject.of(comment)
    column = Subject.column(kind)

    Follow
    |> Ash.Query.filter(^Ash.Expr.ref(column) == ^id)
    |> Ash.read!(Keyword.merge(opts, authorize?: false))
    |> Enum.map(& &1.user_id)
  end

  @doc """
  A comment by its id with no policy, for the listener of `:commented` and
  the jobs of the notifications. A page never calls it.
  """
  @spec comment_for_job(Ecto.UUID.t(), keyword) :: Comment.t() | nil
  def comment_for_job(id, opts) do
    Ash.get!(Comment, id, Keyword.merge(opts, authorize?: false, not_found_error?: false))
  end

  @doc """
  Deletes each comment that one person wrote in the organisation, for a
  person with the power `moderate_comments`: a person who asks a rescue to
  delete what they wrote. Returns the number of comments deleted.
  """
  @spec erase(Ecto.UUID.t(), keyword) :: {:ok, non_neg_integer} | {:error, term}
  def erase(author_id, opts) when is_binary(author_id) do
    Comment
    |> Ash.Query.filter(author_id == ^author_id)
    |> Ash.bulk_destroy(:erase, %{},
      actor: opts[:actor],
      tenant: opts[:tenant],
      strategy: [:stream],
      return_records?: true,
      return_errors?: true,
      notify?: true
    )
    |> case do
      %Ash.BulkResult{status: :success, records: records} -> {:ok, length(records || [])}
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end

  @doc "Whether the role can run `action` of a comment at all."
  @spec role_can?(term, atom) :: boolean
  def role_can?(role, action), do: Rescord.Accounts.granted?(role, Comment, action)

  @doc """
  Whether the role can change or delete this comment, as the policy would
  decide: the writer with the power `comments`, or any comment with the
  power `moderate_comments` for a delete.
  """
  @spec can?(term, term, Comment.t(), :revise | :delete) :: boolean
  def can?(:root, _user, _comment, _action), do: true

  def can?(role, %{id: user_id}, %Comment{} = comment, action) do
    case Rescord.Accounts.Grants.scope(role, Comment, action) do
      {:ok, :all} -> true
      {:ok, :own} -> comment.author_id == user_id
      _none -> false
    end
  end

  def can?(_role, _user, _comment, _action), do: false

  @doc """
  The problems of a refused write, as words for a person, with `nil` for a
  problem of no field.
  """
  @spec problems(term) :: [{atom | nil, String.t()}]
  def problems(%{errors: errors}) when is_list(errors),
    do: errors |> Enum.flat_map(&problem/1) |> Enum.uniq()

  def problems(_error), do: [{nil, "That did not work"}]

  defp problem(%Ash.Error.Changes.Required{field: :body}), do: [{:body, "write the comment"}]
  defp problem(%Ash.Error.Forbidden.Policy{}), do: [{nil, "You cannot do that"}]
  defp problem(%Ash.Error.Changes.StaleRecord{}), do: [{nil, "The comment is gone"}]

  defp problem(%Ash.Error.Changes.InvalidAttribute{field: :body, message: message} = error)
       when is_binary(message),
       do: [{:body, with_values(message, Map.get(error, :vars))}]

  defp problem(%{field: field, message: message} = error)
       when is_atom(field) and not is_nil(field) and is_binary(message),
       do: [{field, with_values(message, Map.get(error, :vars))}]

  defp problem(%{errors: [_ | _]} = inner), do: problems(inner)
  defp problem(_other), do: [{nil, "That did not work"}]

  defp with_values(message, vars) when is_list(vars) do
    Enum.reduce(vars, message, fn {key, value}, text ->
      String.replace(text, "%{#{key}}", to_string(value))
    end)
  end

  defp with_values(message, _vars), do: message
end
