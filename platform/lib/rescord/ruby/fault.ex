defmodule Rescord.Ruby.Fault do
  @moduledoc """
  A fault of Rescord while Ruby wrote a reply: the error that the job of
  the reply raises, in the place of the one that happened.

  Oban keeps the error of a job in the row of the job, with its message
  and its stack trace. The error of a reply can hold words of the
  conversation: the message of an Ash error holds the value that Ash
  refused, and a frame of a stack trace holds the values that a function
  got. So the job raises this one, which has the shape of the error
  (`Rescord.Log.reason/1`) and nothing that a person wrote.
  """

  defexception [:shape]

  @impl true
  def message(%__MODULE__{shape: shape}), do: "Ruby could not write a reply: #{shape}"

  @doc "The fault of an error, and the stack trace with no value of a call."
  @spec of(term, Exception.stacktrace()) :: {Exception.t(), Exception.stacktrace()}
  def of(error, stacktrace) do
    frames =
      Enum.map(stacktrace, fn
        {module, function, arguments, location} when is_list(arguments) ->
          {module, function, length(arguments), location}

        frame ->
          frame
      end)

    {%__MODULE__{shape: Rescord.Log.reason(error)}, frames}
  end
end
