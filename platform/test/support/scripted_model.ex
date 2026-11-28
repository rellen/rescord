defmodule Rescord.Ruby.ScriptedModel do
  @moduledoc """
  A model that answers from a script, for the tests. No request leaves the
  process.

  It takes the place of `ReqLLM` in `AshAi.ToolLoop` (the option
  `req_llm:`). Each request of the loop takes the next step of the script:

      ScriptedModel.script([
        {:tool, "find_residents", %{}},
        {:text, "Biscuit is a goat."}
      ])

  A step is `{:text, text}`, `{:tool, name, arguments}`, `{:refusal, text}`,
  `{:cut, text}` (the limit of tokens cut the answer), `{:error, reason}`
  or `{:raise, message}` (a fault in the middle of the loop, in the process
  that asked). A request with no step left raises there too.
  `requests/0` gives what the loop sent, so that a test reads the prompt.

  The script is in the process that runs the test, so tests run `async`.
  A turn that runs in a task reads the script of its caller.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias ReqLLM.{StreamChunk, StreamResponse}
  alias ReqLLM.StreamResponse.MetadataHandle

  @usage %{input_tokens: 1_000, output_tokens: 50, total_tokens: 1_050}

  def script(steps) when is_list(steps) do
    {:ok, agent} = Agent.start_link(fn -> %{steps: steps, requests: []} end)
    Process.put(__MODULE__, agent)
    :ok
  end

  def requests, do: Agent.get(agent!(), &Enum.reverse(&1.requests))

  @doc "As `ReqLLM.stream_text/3`."
  def stream_text(model, messages, opts) do
    step =
      Agent.get_and_update(agent!(), fn state ->
        request = %{model: model, messages: messages, opts: opts}

        case state.steps do
          [step | rest] -> {step, %{state | steps: rest, requests: [request | state.requests]}}
          [] -> {:none, state}
        end
      end)

    respond(step, model, messages)
  end

  defp respond(:none, _model, _messages),
    do: raise("the script of the model has no step for this request")

  defp respond({:raise, message}, _model, _messages), do: raise(message)
  defp respond({:error, reason}, _model, _messages), do: {:error, reason}

  defp respond({:text, text}, model, messages),
    do: response(words(text), :stop, "end_turn", model, messages)

  defp respond({:refusal, text}, model, messages),
    do: response(words(text), :content_filter, "refusal", model, messages)

  defp respond({:cut, text}, model, messages),
    do: response(words(text), :length, "max_tokens", model, messages)

  defp respond({:tool, name, arguments}, model, messages) do
    id = "toolu_" <> Integer.to_string(System.unique_integer([:positive]))
    chunks = [StreamChunk.tool_call(name, arguments, %{id: id})]
    response(chunks, :tool_calls, "tool_use", model, messages)
  end

  # One chunk for each word, as a provider sends an answer in pieces.
  defp words(text) do
    text
    |> String.split(~r/(?<= )/)
    |> Enum.map(&StreamChunk.text/1)
  end

  defp response(chunks, finish_reason, stop_reason, model, messages) do
    usage = StreamChunk.meta(%{usage: @usage})

    meta =
      StreamChunk.meta(%{
        finish_reason: finish_reason,
        terminal?: true,
        provider_meta: %{"stop_reason" => stop_reason}
      })

    {:ok, handle} =
      MetadataHandle.start_link(fn -> %{usage: @usage, finish_reason: finish_reason} end)

    {:ok,
     %StreamResponse{
       stream: chunks ++ [usage, meta],
       metadata_handle: handle,
       cancel: fn -> :ok end,
       model: ReqLLM.model!(model),
       context: ReqLLM.Context.new(messages)
     }}
  end

  defp agent! do
    Process.get(__MODULE__) ||
      Enum.find_value(Process.get(:"$callers", []), fn pid ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dictionary} -> Keyword.get(dictionary, __MODULE__)
          nil -> nil
        end
      end) || raise "no script: call ScriptedModel.script/1 first"
  end
end
