defmodule Rescord.Ruby.Events do
  @moduledoc """
  What the page of a conversation hears while Ruby answers (ADR 0069):
  messages on the topic of the conversation, on `Rescord.PubSub`.

      {:ruby, :text, reply_id, text}     # the whole text of the reply so far
      {:ruby, :step, reply_id, step}     # a call of a tool, when it starts and when it ends
      {:ruby, :reply, reply_id, state}   # :streaming, then how it ended

  A message holds the words of the reply, a step or the state, and
  nothing of a tool result: those hold raw records. The text is the whole
  text so far, so a page that joins late, or that missed a message, is
  right at the next one.

  Only `Rescord.Ruby.subscribe/2` puts a page on a topic, and it asks
  first whether the conversation is one of the person. The id of a
  conversation is a random UUID, and the topic holds nothing else.
  """

  @pubsub Rescord.PubSub

  @doc "The topic of a conversation."
  @spec topic(String.t()) :: String.t()
  def topic(conversation_id) when is_binary(conversation_id), do: "ruby:" <> conversation_id

  @doc "Tells the pages of the conversation the whole text of a reply so far."
  @spec text(map, String.t()) :: :ok
  def text(%{id: id, conversation_id: conversation_id}, text) when is_binary(text),
    do: broadcast(conversation_id, {:ruby, :text, id, text})

  @doc """
  Tells the pages of the conversation a step of a reply, as
  `Rescord.Ruby.Steps` made it: what code made of a call of a tool, and
  never its result.
  """
  @spec step(map, map) :: :ok
  def step(%{id: id, conversation_id: conversation_id}, %{"call_id" => _} = step),
    do: broadcast(conversation_id, {:ruby, :step, id, step})

  @doc "Tells the pages of the conversation the state of a reply."
  @spec reply(map, atom) :: :ok
  def reply(%{id: id, conversation_id: conversation_id}, state) when is_atom(state),
    do: broadcast(conversation_id, {:ruby, :reply, id, state})

  @doc false
  @spec listen(String.t()) :: :ok
  def listen(conversation_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(conversation_id))

  @doc false
  @spec leave(String.t()) :: :ok
  def leave(conversation_id), do: Phoenix.PubSub.unsubscribe(@pubsub, topic(conversation_id))

  defp broadcast(conversation_id, message),
    do: Phoenix.PubSub.broadcast(@pubsub, topic(conversation_id), message)
end
