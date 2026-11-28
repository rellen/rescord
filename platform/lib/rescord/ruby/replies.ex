defmodule Rescord.Ruby.Replies do
  @moduledoc """
  The rows of a reply, which only Ruby writes (ADR 0069), and the history
  of a conversation as the model gets it.

  The job of a reply calls these (`Rescord.Ruby.Changes.Respond`). No
  person is there, so they ask no policy: the job checked who asked.

  A conversation can go while its reply is written: its member removes
  it, and its messages go with it. A write then finds no row, and answers
  `:gone`.
  """

  require Ash.Query

  alias AshAi.Transcript
  alias Rescord.Ruby.Message

  @doc """
  Makes the reply to a message of a member, with no word yet. `:taken`
  when the message has a reply: another job got there first.
  """
  @spec open(Message.t(), term) :: {:ok, Message.t()} | :taken
  def open(%Message{source: :user} = message, tenant) do
    Message
    |> Ash.Changeset.for_create(
      :open_reply,
      %{
        conversation_id: message.conversation_id,
        owner_id: message.owner_id,
        response_to_id: message.id
      },
      options(tenant)
    )
    |> Ash.create()
    |> case do
      {:ok, reply} ->
        {:ok, reply}

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        if Enum.any?(errors, &taken?/1), do: :taken, else: raise(error)

      {:error, error} ->
        raise error
    end
  end

  # The identity `one_reply`.
  defp taken?(%Ash.Error.Changes.InvalidAttribute{field: :response_to_id}), do: true
  defp taken?(_other), do: false

  @doc "Saves the words and the parts of a reply so far."
  @spec save(Message.t(), String.t(), [map], term) :: :ok | :gone
  def save(%Message{} = reply, text, parts, tenant),
    do: write(reply, :grow, %{text: text, parts: parts}, tenant)

  @doc "Writes the end of a reply."
  @spec close(Message.t(), map, term) :: :ok | :gone
  def close(%Message{} = reply, values, tenant), do: write(reply, :close, values, tenant)

  defp write(reply, action, values, tenant) do
    reply
    |> Ash.Changeset.for_update(action, values, options(tenant))
    |> Ash.update()
    |> case do
      {:ok, _reply} ->
        :ok

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        if Enum.any?(errors, &match?(%Ash.Error.Changes.StaleRecord{}, &1)),
          do: :gone,
          else: raise(error)

      {:error, error} ->
        raise error
    end
  end

  @doc """
  Whether the member stopped the reply to this message. A message that is
  gone is a stop too: its conversation was removed.
  """
  @spec stop_asked?(Message.t(), term) :: boolean
  def stop_asked?(%Message{id: id}, tenant) do
    Message
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.select([:stop_requested])
    |> Ash.read_one!(options(tenant))
    |> case do
      nil -> true
      %{stop_requested: asked?} -> asked?
    end
  end

  @doc """
  The conversation up to this message of the member, as the messages of a
  request. The system prompt is not among them: the loop adds it.

  A message of a member is its header and its text, as they were stored. A
  reply is its parts, so the model gets its own tool calls and their
  results again, byte for byte. The thinking of a reply goes with it only
  while `fingerprint`, the hash of the prompt and the tools of today, is
  the one that made it: a provider refuses thinking that another prompt
  made.

  A reply that failed or that the member stopped has the parts that
  arrived whole. The loop answers a tool call that got no result itself.
  """
  @spec chain(Message.t(), String.t(), term) :: [ReqLLM.Message.t()]
  def chain(%Message{id: id, conversation_id: conversation_id}, fingerprint, tenant) do
    Message
    |> Ash.Query.filter(conversation_id == ^conversation_id and id <= ^id)
    |> Ash.Query.sort(id: :asc)
    |> Ash.read!(options(tenant))
    |> Enum.flat_map(fn
      %{source: :user} = said -> [ReqLLM.Context.user((said.header || "") <> said.text)]
      %{source: :ruby} = reply -> replay(reply, fingerprint)
    end)
  end

  defp replay(%{parts: parts, prompt_fingerprint: made_with}, fingerprint) do
    messages = Transcript.from_parts(parts)
    if made_with == fingerprint, do: messages, else: Transcript.strip_reasoning(messages)
  end

  @doc """
  Where a conversation stands for a new message of its member:

    * `:running` - a message of the member has no reply yet, or its reply
      is not at its end;
    * `:closed` - the provider refused to answer in it, and would refuse
      the same history again;
    * `{:open, last, held}` - it takes a message. `last` is the time of
      the newest message of the member, or `nil` in a new conversation.
      `held` is the tokens that the conversation holds: what the next
      request starts from.

  The provider reports the size of each prompt, and a reply keeps the
  size after its last request (`prompt_tokens`). So `held` is that number
  of the newest reply that has one, and the words of the member that came
  after it, at three bytes for a token, which counts too many for English:
  the safe side. A new conversation holds 0: the prompt and the tools are
  far below the limit of a request.
  """
  @spec standing(String.t(), term) ::
          :running | :closed | {:open, DateTime.t() | nil, non_neg_integer}
  def standing(conversation_id, tenant) do
    rows =
      Message
      |> Ash.Query.filter(conversation_id == ^conversation_id)
      |> Ash.Query.select([
        :source,
        :state,
        :reason,
        :response_to_id,
        :inserted_at,
        :prompt_tokens,
        :header,
        :text
      ])
      |> Ash.Query.sort(id: :asc)
      |> Ash.read!(options(tenant))

    {said, replies} = Enum.split_with(rows, &(&1.source == :user))
    answered = MapSet.new(replies, & &1.response_to_id)

    cond do
      Enum.any?(replies, &(&1.reason == :refused)) -> :closed
      Enum.any?(replies, &(&1.state == :streaming)) -> :running
      Enum.any?(said, &(not MapSet.member?(answered, &1.id))) -> :running
      true -> {:open, said |> List.last() |> then(&(&1 && &1.inserted_at)), held(rows)}
    end
  end

  # From the newest row back to the newest reply that knows its size.
  defp held(rows) do
    rows
    |> Enum.reverse()
    |> Enum.reduce_while(0, fn
      %{source: :ruby, prompt_tokens: tokens}, bytes when is_integer(tokens) ->
        {:halt, {:tokens, tokens + tokens(bytes)}}

      %{source: :user} = said, bytes ->
        {:cont, bytes + byte_size(said.header || "") + byte_size(said.text)}

      _reply, bytes ->
        {:cont, bytes}
    end)
    |> case do
      {:tokens, tokens} -> tokens
      bytes -> tokens(bytes)
    end
  end

  @doc "The tokens of this many bytes of text, at three bytes for a token, rounded up."
  @spec tokens(non_neg_integer) :: non_neg_integer
  def tokens(bytes) when is_integer(bytes) and bytes >= 0, do: div(bytes + 2, 3)

  defp options(tenant), do: [tenant: tenant, authorize?: false]
end
