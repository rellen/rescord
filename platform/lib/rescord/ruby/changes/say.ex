defmodule Rescord.Ruby.Changes.Say do
  @moduledoc """
  What `say` does to a new message of a member: the source is the member,
  the text has no space around it and is within its limit, the
  conversation is one of the actor and takes a message, the message gets
  its header, and the conversation gets the time of the message, and its
  title from the first one.

  A conversation takes one message at a time: while Ruby answers, a second
  message is refused. The change locks the row of the conversation until
  the message is saved, so two messages of one moment cannot both pass. A
  conversation where the provider refused to answer takes no more: the
  same history would be refused again.

  A message is refused, with a reason of `Rescord.Ruby.Reason`, when the
  allowance of the month is used (`Rescord.Ruby.Allowance`), when the
  member has used their share of the month (ADR 0117), and when the
  conversation with the new message would be longer than one request of
  the provider takes. The size is the one that the provider reported for
  the last request, and the words since.

  The header is what the model gets before the text, and no page shows
  (`Rescord.Ruby.Prompt`). The first message of a conversation has the
  rescue, the role of the member, the day and the time zone, and the
  record that the conversation is about. A message of a later day has the
  new day. It is never an input, and it is stored: Rescord sends it again
  as it was.

  With no user, the change does nothing, and the policy refuses the
  action.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts
  alias Rescord.Accounts.Checks.Granted
  alias Rescord.Accounts.User
  alias Rescord.Ruby.{Allowance, Conversation, Prompt, Provider, Replies, Title}
  alias Rescord.Ruby.LLM.Profile

  # The most characters of what a member types in one message.
  @most 4_000

  @doc "The most characters of one message of a member."
  @spec most() :: pos_integer
  def most, do: @most

  @impl true
  def change(changeset, _opts, %{actor: %User{} = user}) do
    changeset
    |> Ash.Changeset.force_change_attribute(:source, :user)
    |> text()
    |> Ash.Changeset.before_action(&place(&1, user))
    |> Ash.Changeset.after_action(&note/2)
  end

  def change(changeset, _opts, _context), do: changeset

  defp text(changeset) do
    text = changeset |> Ash.Changeset.get_attribute(:text) |> to_string() |> String.trim()

    cond do
      text == "" ->
        Ash.Changeset.add_error(changeset, field: :text, message: "say something first")

      String.length(text) > @most ->
        Ash.Changeset.add_error(changeset,
          field: :text,
          message: "is longer than %{max} characters",
          vars: [max: @most]
        )

      true ->
        Ash.Changeset.force_change_attribute(changeset, :text, text)
    end
  end

  # The conversation of the message, inside the transaction of the action.
  # A conversation that is not there and a conversation of another person
  # get the same answer, so the answer says nothing about another person.
  defp place(%{valid?: false} = changeset, _user), do: changeset

  defp place(changeset, %User{id: user_id} = user) do
    id = Ash.Changeset.get_attribute(changeset, :conversation_id)

    # The lock holds a second message of the same conversation until this
    # one is saved.
    found =
      id &&
        Ash.get(
          Conversation,
          id,
          [not_found_error?: false, lock: :for_update] ++ options(changeset)
        )

    case found do
      {:ok, %Conversation{owner_id: ^user_id} = conversation} ->
        changeset
        |> Ash.Changeset.put_context(:ruby_conversation, conversation)
        |> turn(conversation, user)

      _other ->
        Ash.Changeset.add_error(changeset,
          field: :conversation_id,
          message: "is no conversation of this person"
        )
    end
  end

  defp turn(changeset, conversation, user) do
    case Replies.standing(conversation.id, changeset.tenant) do
      :running ->
        Ash.Changeset.add_error(changeset,
          field: :text,
          message: "Ruby is still answering: wait for the answer, or stop it"
        )

      :closed ->
        Ash.Changeset.add_error(changeset,
          field: :text,
          message: "this conversation takes no more messages: start a new one"
        )

      {:open, last, held} ->
        text = Ash.Changeset.get_attribute(changeset, :text)

        cond do
          not Allowance.room?(changeset.tenant) ->
            refuse(changeset, :allowance, "the allowance of the month is used")

          not Allowance.member_room?(changeset.tenant, user.id) ->
            refuse(changeset, :member_allowance, "your share of the month is used")

          full?(held + Replies.tokens(byte_size(text)), request_tokens(changeset.tenant)) ->
            refuse(changeset, :too_long, "this conversation is full: start a new one")

          true ->
            Ash.Changeset.force_change_attribute(
              changeset,
              :header,
              header(conversation, last, user, changeset.tenant)
            )
        end
    end
  end

  # A refusal with a reason of `Rescord.Ruby.Reason`, which a page turns
  # into its own sentence (`Rescord.Ruby.refusal/1`).
  defp refuse(changeset, reason, words) do
    # A key that the error does not know goes to its `vars`.
    Ash.Changeset.add_error(changeset, field: :text, message: words, reason: reason)
  end

  defp full?(tokens, limit), do: is_integer(limit) and tokens > limit

  # The most tokens of one request with the provider of the organisation.
  # The row of the provider says it, and no key is decrypted. With no
  # provider there is no limit to hold: the job then ends the reply as
  # failed, and sends nothing.
  defp request_tokens(tenant) do
    with id when is_binary(id) <- Rescord.Ruby.settings(tenant).provider_id,
         {:ok, %Provider{} = provider} <-
           Ash.get(Provider, id, authorize?: false, not_found_error?: false) do
      Profile.context_tokens(provider)
    else
      _no_provider -> nil
    end
  end

  # The first message has the whole header. A message of a later day, as
  # the organisation counts its days, has the new day. Any other has none.
  defp header(conversation, last, user, tenant) do
    organisation = Accounts.organisation_of(tenant)
    today = Accounts.local_date(organisation, DateTime.utc_now())

    cond do
      is_nil(last) -> opening(user, tenant, conversation.about)
      Accounts.local_date(organisation, last) != today -> Prompt.day_note(today)
      true -> nil
    end
  end

  @doc """
  The header of the first message of a conversation of this member: the
  rescue, the role of the member, the day there and its time zone, and
  what the conversation is about (`about`, or `nil`). The evaluation set
  asks here too, so that its questions start as a conversation does.
  """
  @spec opening(User.t(), term, String.t() | nil) :: String.t()
  def opening(%User{} = user, tenant, about) do
    organisation = Accounts.organisation_of(tenant)

    Prompt.header(%{
      organisation: organisation.name,
      role: role_name(user, tenant),
      today: Accounts.local_date(organisation, DateTime.utc_now()),
      time_zone: organisation.time_zone,
      about: about
    })
  end

  # The name of the role, as the organisation named it. It says what the
  # member does there, and is no name of a person.
  defp role_name(user, tenant) do
    case Granted.role_of(user, tenant) do
      nil -> nil
      role -> to_string(role.name)
    end
  end

  defp note(changeset, message) do
    conversation = changeset.context.ruby_conversation

    conversation
    |> Ash.Changeset.for_update(
      :touch,
      %{
        last_message_at: message.inserted_at,
        title: conversation.title || Title.of(message.text)
      },
      options(changeset)
    )
    |> Ash.update()
    |> case do
      {:ok, _conversation} -> {:ok, message}
      {:error, error} -> {:error, error}
    end
  end

  # Rescord reads and touches the conversation itself, after the check of
  # the owner above: `touch` is in no grant.
  defp options(changeset),
    do: [
      tenant: changeset.tenant,
      context: Rescord.Correlation.context(changeset),
      authorize?: false
    ]
end
