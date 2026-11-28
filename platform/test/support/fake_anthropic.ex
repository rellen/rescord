defmodule Rescord.FakeAnthropic do
  @moduledoc """
  A server on this machine that speaks the Messages API of Anthropic as a
  stream, from a script. The real ReqLLM and the real HTTP client talk to
  it, so a test with it covers what a scripted model skips: the body of the
  request, the events of the stream, the errors of HTTP and a stream that a
  member stops.

      {:ok, fake} = FakeAnthropic.start_link([{:text, "Hello."}])
      profile = %Profile{..., base_url: FakeAnthropic.url(fake), api_key: "test"}

  A step is `{:text, text}`, `{:tool, name, input}`, `{:refusal, text}`,
  `{:cut, text}`, `{:slow, text, ms}` (one word, then a wait for each next
  word), `{:break, text}` (the text, and then the connection breaks with no
  end) or `{:status, status, body}`. `requests/1` gives the requests
  that arrived, with the body decoded.

  A request to another path gets 404, and is kept too: a test reads what
  ReqLLM sends to a server of another kind.

  A provider of a hosted kind takes an address with TLS only, so a test of
  a whole reply cannot save the address of the fake. `via/1` sends each
  request of `Rescord.Ruby.LLM.Client` to the fake until the test ends:
  the real ReqLLM, with one option changed.
  """

  use Agent
  use Boundary, top_level?: true, check: [in: false, out: false]

  def start_link(steps) do
    {:ok, agent} = Agent.start_link(fn -> %{steps: steps, requests: [], port: nil} end)

    {:ok, server} =
      Bandit.start_link(
        plug: {__MODULE__.Plug, agent},
        ip: :loopback,
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    Agent.update(agent, &%{&1 | port: port})
    {:ok, agent}
  end

  @doc """
  Sends each request of the assistant to this fake, with the real ReqLLM,
  until the test ends. A test that calls this does not run beside others.
  """
  def via(agent) do
    before = Application.get_env(:rescord, :ruby_llm)
    Application.put_env(:rescord, :fake_anthropic_url, url(agent))
    Application.put_env(:rescord, :ruby_llm, __MODULE__.Via)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:rescord, :ruby_llm, before)
      Application.delete_env(:rescord, :fake_anthropic_url)
    end)
  end

  defmodule Via do
    @moduledoc false
    def stream_text(model, messages, opts) do
      url = Application.fetch_env!(:rescord, :fake_anthropic_url)
      ReqLLM.stream_text(model, messages, Keyword.put(opts, :base_url, url))
    end
  end

  # The base of Anthropic has no "/v1": ReqLLM adds the path.
  def url(agent), do: "http://127.0.0.1:#{Agent.get(agent, & &1.port)}"
  def requests(agent), do: Agent.get(agent, &Enum.reverse(&1.requests))

  def keep(agent, request),
    do: Agent.update(agent, &%{&1 | requests: [request | &1.requests]})

  def next(agent, request) do
    Agent.get_and_update(agent, fn state ->
      case state.steps do
        [step | rest] -> {step, %{state | steps: rest, requests: [request | state.requests]}}
        [] -> {{:status, 500, %{}}, %{state | requests: [request | state.requests]}}
      end
    end)
  end

  defmodule Plug do
    @moduledoc false
    import Elixir.Plug.Conn

    def init(agent), do: agent

    def call(%{method: "POST", request_path: "/v1/messages"} = conn, agent) do
      {:ok, body, conn} = read_body(conn, length: 20_000_000)

      respond(conn, Rescord.FakeAnthropic.next(agent, request(conn, body)))
    end

    def call(%{method: "POST"} = conn, agent) do
      {:ok, body, conn} = read_body(conn, length: 20_000_000)
      Rescord.FakeAnthropic.keep(agent, request(conn, body))
      send_resp(conn, 404, "")
    end

    def call(conn, _agent), do: send_resp(conn, 404, "")

    defp request(conn, body) do
      %{path: conn.request_path, body: Jason.decode!(body), headers: Map.new(conn.req_headers)}
    end

    defp respond(conn, {:status, status, body}) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(body))
    end

    defp respond(conn, {:text, text}),
      do: stream(conn, text_events(words(text)), "end_turn", 0)

    defp respond(conn, {:refusal, text}),
      do: stream(conn, text_events(words(text)), "refusal", 0)

    defp respond(conn, {:cut, text}),
      do: stream(conn, text_events(words(text)), "max_tokens", 0)

    defp respond(conn, {:slow, text, ms}),
      do: stream(conn, text_events(words(text)), "end_turn", ms)

    # The events of the text, and then the process of the connection dies:
    # the client gets no `message_delta` and no end of the body.
    defp respond(conn, {:break, text}) do
      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> send_chunked(200)

      [{"message_start", %{message: message()}} | text_events(words(text))]
      |> Enum.take(length(words(text)) + 2)
      |> Enum.each(fn {type, data} -> {:ok, _conn} = chunk(conn, frame(type, data)) end)

      Process.sleep(50)
      exit(:shutdown)
    end

    defp respond(conn, {:tool, name, input}) do
      id = "toolu_" <> Integer.to_string(System.unique_integer([:positive]))

      events = [
        {"content_block_start",
         %{index: 0, content_block: %{type: "tool_use", id: id, name: name, input: %{}}}},
        {"content_block_delta",
         %{index: 0, delta: %{type: "input_json_delta", partial_json: Jason.encode!(input)}}},
        {"content_block_stop", %{index: 0}}
      ]

      stream(conn, events, "tool_use", 0)
    end

    defp words(text), do: String.split(text, ~r/(?<= )/)

    defp text_events(words) do
      [{"content_block_start", %{index: 0, content_block: %{type: "text", text: ""}}}] ++
        Enum.map(words, fn word ->
          {"content_block_delta", %{index: 0, delta: %{type: "text_delta", text: word}}}
        end) ++ [{"content_block_stop", %{index: 0}}]
    end

    # The numbers of a second question in a conversation: a small new part,
    # most of the prompt from the cache, and a little written to the cache.
    @usage %{
      input_tokens: 12,
      cache_read_input_tokens: 5_000,
      cache_creation_input_tokens: 300,
      cache_creation: %{ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 300},
      output_tokens: 1
    }

    defp message do
      %{
        id: "msg_fake",
        type: "message",
        role: "assistant",
        model: "claude-opus-5-5",
        content: [],
        stop_reason: nil,
        usage: @usage
      }
    end

    defp frame(type, data),
      do: "event: #{type}\ndata: #{Jason.encode!(Map.put(data, :type, type))}\n\n"

    defp stream(conn, events, stop_reason, wait_ms) do
      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> send_chunked(200)

      all =
        [{"message_start", %{message: message()}}] ++
          events ++
          [
            {"message_delta",
             %{
               delta: %{stop_reason: stop_reason, stop_sequence: nil},
               usage: %{output_tokens: 40}
             }},
            {"message_stop", %{}}
          ]

      Enum.reduce_while(all, conn, fn {type, data}, conn ->
        if wait_ms > 0 and type == "content_block_delta", do: Process.sleep(wait_ms)

        case chunk(conn, frame(type, data)) do
          {:ok, conn} -> {:cont, conn}
          # The client closed the stream: the member stopped the answer.
          {:error, _closed} -> {:halt, conn}
        end
      end)
    end
  end
end
