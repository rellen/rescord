defmodule Rescord.Ruby.Changes.Say do
  @moduledoc """
  What `say` does to a new message of a member: the source is the member,
  the text has no space around it and is within its limit, the
  conversation is one of the actor, and the conversation gets the time of
  the message, and its title from the first one.

  With no user, the change does nothing, and the policy refuses the
  action.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts.User
  alias Rescord.Ruby.{Conversation, Title}

  # The most characters of what a member types in one message.
  @most 4_000

  @doc "The most characters of one message of a member."
  @spec most() :: pos_integer
  def most, do: @most

  @impl true
  def change(changeset, _opts, %{actor: %User{id: user_id}}) do
    changeset
    |> Ash.Changeset.force_change_attribute(:source, :user)
    |> text()
    |> Ash.Changeset.before_action(&own_conversation(&1, user_id))
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

  # A conversation that is not there and a conversation of another person
  # get the same answer, so the answer says nothing about another person.
  defp own_conversation(changeset, user_id) do
    id = Ash.Changeset.get_attribute(changeset, :conversation_id)

    case id && Ash.get(Conversation, id, [not_found_error?: false] ++ options(changeset)) do
      {:ok, %Conversation{owner_id: ^user_id} = conversation} ->
        Ash.Changeset.put_context(changeset, :ruby_conversation, conversation)

      _other ->
        Ash.Changeset.add_error(changeset,
          field: :conversation_id,
          message: "is no conversation of this person"
        )
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
      context: Map.take(changeset.context, [:shared]),
      authorize?: false
    ]
end
