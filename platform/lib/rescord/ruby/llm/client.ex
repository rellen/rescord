defmodule Rescord.Ruby.LLM.Client do
  @moduledoc """
  The module that `AshAi.ToolLoop` calls in place of `ReqLLM` (its option
  `req_llm:`). It passes each request to ReqLLM, and keeps a record of each:
  the tokens, and why the model stopped.

  Ruby needs the record because `AshAi.ToolLoop` does not give it:

    * The loop does not say why the model stopped. A refusal, and an answer
      that the limit of tokens cut, both look like an answer with less text.
    * The loop gives the tokens only in its last event. A turn that fails, or
      that a member stops, has no last event, and the provider bills it.

  The provider reports the tokens of the prompt when a stream starts, and
  the tokens of the answer when it ends. So the record of a stream that
  stopped early has the prompt, and no answer.

  A stream runs in the process that reads it, the process of the turn. The
  records are in the dictionary of that process, and `take_requests/0`
  empties them.
  """

  alias Rescord.Ruby.LLM.Cost

  @key {__MODULE__, :requests}

  @type request :: %{
          usage: Cost.usage(),
          finish_reason: atom | nil,
          stop_reason: String.t() | nil
        }

  @doc "As `ReqLLM.stream_text/3`, and keeps a record of the request."
  @spec stream_text(term, term, keyword) :: {:ok, ReqLLM.StreamResponse.t()} | {:error, term}
  def stream_text(model, messages, opts) do
    case inner().stream_text(model, messages, opts) do
      {:ok, %ReqLLM.StreamResponse{} = response} ->
        Process.put(@key, [new_request() | Process.get(@key, [])])
        {:ok, %{response | stream: Stream.each(response.stream, &note/1)}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc "The records of the requests of this process, the first one first. Forgets them."
  @spec take_requests() :: [request]
  def take_requests, do: @key |> Process.delete() |> List.wrap() |> Enum.reverse()

  # A seam for the tests, and no setting (ADR 0068): `config/test.exs` puts
  # a scripted model here, so that no test reaches a provider. Everything
  # above it is the real code.
  defp inner, do: Application.get_env(:rescord, :ruby_llm, ReqLLM)

  defp new_request do
    %{
      usage: %{input: 0, cache_read: 0, cache_write: 0, output: 0},
      finish_reason: nil,
      stop_reason: nil
    }
  end

  defp note(%ReqLLM.StreamChunk{type: :meta, metadata: meta}) do
    case Process.get(@key) do
      [request | rest] ->
        request =
          request
          |> note_usage(Map.get(meta, :usage))
          |> note_stop(meta)

        Process.put(@key, [request | rest])

      # Another process reads the stream than the one that asked for it.
      # `AshAi.ToolLoop` does not do that.
      _none ->
        :ok
    end
  end

  defp note(_chunk), do: :ok

  # A provider reports its tokens in more than one event. Each count only
  # grows, so the record keeps the largest of each.
  defp note_usage(request, usage) when is_map(usage) do
    read = count(usage, [:cache_read_tokens, :cache_read_input_tokens, :cached_tokens])
    written = count(usage, [:cache_write_tokens, :cache_creation_input_tokens])
    input = count(usage, [:input_tokens])

    # Anthropic counts the tokens of the cache apart from `input_tokens`,
    # and the runs of this project checked that. A provider of the OpenAI
    # kind counts them inside it, and says so in the usage that ReqLLM gives
    # at the end. Nothing here checked what its stream holds on the way.
    fresh = if usage[:input_includes_cached], do: max(input - read - written, 0), else: input

    seen = %{
      input: fresh,
      cache_read: read,
      cache_write: written,
      output: count(usage, [:output_tokens])
    }

    %{request | usage: Map.merge(request.usage, seen, fn _key, a, b -> max(a, b) end)}
  end

  defp note_usage(request, _none), do: request

  defp note_stop(request, %{finish_reason: reason} = meta) when not is_nil(reason) do
    # ReqLLM keeps the word of the provider beside its own.
    %{request | finish_reason: reason, stop_reason: get_in(meta, [:provider_meta, "stop_reason"])}
  end

  defp note_stop(request, _meta), do: request

  defp count(usage, keys) do
    Enum.find_value(keys, 0, fn key ->
      case Map.get(usage, key) do
        n when is_integer(n) and n > 0 -> n
        _other -> nil
      end
    end)
  end
end
