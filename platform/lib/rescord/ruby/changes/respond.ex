defmodule Rescord.Ruby.Changes.Respond do
  @moduledoc """
  Writes the reply to a message of a member (ADR 0069): runs the tool loop
  of `AshAi` as that member, in that organisation, and saves the reply as
  it arrives. The job of the trigger `respond` runs it, and nothing else.

  ## What it does

    1. It makes the row of the reply (`Rescord.Ruby.Replies.open/2`). A
       message has one reply, so a second job finds it taken and stops.
    2. It checks the person again: the job has the member who said the
       message, and Ruby is still on for them. Then it reads the profile
       of the provider with its key (`Rescord.Ruby.LLM.profile/1`), the
       one place that decrypts. A check that fails ends the reply as
       failed, and sends nothing.
    3. It reads the stream of `AshAi.ToolLoop.stream/2`. The words and the
       parts so far go to the row, the words at most once a second. Between
       two events it reads, at most once a second, whether the member
       stopped the reply. To leave the stream closes the request.
    4. It writes the end: the state and the reason
       (`Rescord.Ruby.ReplyState`, `Rescord.Ruby.Reason`), the model, the
       tokens and their price.

  ## What the runs of the design found

    * ReqLLM raises an error of the provider, and a connection that
      breaks, out of the stream. So the stream is read inside a rescue,
      and the words that arrived are kept beside the reader, in the
      dictionary of the process.
    * The tokens come from `Rescord.Ruby.LLM.Client.take_requests/0`, and
      not from the last event of the loop: a reply that failed or that the
      member stopped has no last event, and the provider bills it. The
      provider reports the tokens of an answer at its end, so an answer
      that ended early counts the bytes that arrived, three for a token.
    * A refusal and an answer that the limit cut look like any other end
      to the loop. `Client` has the reason of each request.

  ## What goes to the log

  The state and the reason of a reply that failed, and never the error: an
  error of ReqLLM can hold the body of the request, which is the
  conversation. A fault of Rescord in the middle ends the reply as failed
  with the reason `:unknown`, and the job raises `Rescord.Ruby.Fault`,
  which has the shape of the error and none of its words.

  ## What it counts

  After a reply that sent a request, the tokens and their price are added
  to the use of the month (`Rescord.Ruby.Allowance`), whatever the end of
  the reply. The allowance itself is asked by `say`, before the reply.

  The reply keeps the tokens that the conversation holds after it
  (`prompt_tokens`): the prompt and the answer of its last request, as the
  provider reported them, and what came after. `say` reads it to refuse a
  message in a conversation that is full. Inside a reply, a result of a
  tool that would take the next request above the limit of the provider
  ends the reply with the reason `:too_long`, and that request is not
  sent.

  Each reply sends one event of telemetry, `[:rescord, :ruby, :reply,
  :stop]`, with its counts, its state and its reason, and nothing else.
  """

  use Ash.Resource.Change

  require Logger

  alias AshAi.Transcript
  alias Rescord.Accounts.User
  alias Rescord.Ruby.{Allowance, Fault, LLM, Message, Prompt, Reason, Replies, Toolbox}
  alias Rescord.Ruby.LLM.{Client, Cost}

  # The words so far go to the row at most this often. The parts go when
  # a turn of the model or a result of a tool is whole.
  @save_ms 1_000

  # The row of the message is read for a stop at most this often.
  @stop_ms 1_000

  # A failure that is a fault of the setup or of Rescord is an error in
  # the log. A busy or a slow provider is a warning.
  @errors [:request_refused, :key_refused, :provider_limit, :unknown]

  @kept {__MODULE__, :kept}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      answer(changeset.data, context.actor, changeset.tenant)
      changeset
    end)
  end

  defp answer(%Message{source: :user} = message, actor, tenant) do
    case Replies.open(message, tenant) do
      {:ok, reply} -> write(message, reply, actor, tenant)
      :taken -> :ok
    end
  end

  defp answer(_reply, _actor, _tenant), do: :ok

  defp write(message, reply, actor, tenant) do
    with :ok <- asker(message, actor, tenant),
         {:ok, profile} <- LLM.profile(tenant) do
      acc = %{
        message: message,
        reply: reply,
        tenant: tenant,
        text: "",
        # The words of the request that runs now, for the count of an answer
        # that ended early.
        unfinished: "",
        # The bytes of the tool results that the next request adds.
        added: 0,
        # The most tokens of one request.
        limit: profile.context_tokens,
        parts: [],
        saved_at: now(),
        checked_at: now(),
        result: nil,
        error: nil,
        stopped?: false
      }

      # Records of an earlier reply of this process, if one crashed.
      _old = Client.take_requests()
      Process.delete(@kept)

      try do
        run(acc, actor, profile)
      rescue
        # Not the provider: a fault in a tool or in Rescord. The reply
        # must not stay as one that is written, and Oban must record that
        # the job failed. The job runs one time, so nothing tries again.
        error ->
          {fault, frames} = Fault.of(error, __STACKTRACE__)
          end_crashed(acc, profile)
          reraise fault, frames
      end
    else
      {:error, reason} ->
        log(:failed, reason)
        Replies.close(reply, %{state: :failed, reason: reason}, tenant)
        tell(:failed, reason, 0, Cost.sum([]), 0)
    end
  end

  # The end of a reply after a fault, with the words that arrived. When
  # this fails too, such as with no database, the first fault is the one
  # that the job raises.
  defp end_crashed(acc, profile) do
    finish(kept(%{acc | error: :crashed}), profile, nil)
  rescue
    _error -> :ok
  end

  # The job has the member who said the message, and that member can still
  # ask Ruby here: a role can lose the power, and an administrator can
  # turn Ruby off, while the job waits.
  defp asker(%Message{owner_id: id}, %User{id: id} = user, tenant) do
    if Rescord.Ruby.available?(user, tenant), do: :ok, else: {:error, :unknown}
  end

  defp asker(_message, _actor, _tenant), do: {:error, :unknown}

  defp run(acc, user, profile) do
    options = Toolbox.options(user, acc.tenant, profile)

    # This lists the tools, and the loop lists them again: the queries of
    # the policy run twice for a reply. Fine at this size.
    fingerprint = Transcript.fingerprint(Prompt.system(), AshAi.list_tools(options))

    # A stop can come before the job starts. Then nothing is sent.
    acc =
      if Replies.stop_asked?(acc.message, acc.tenant) do
        %{acc | stopped?: true}
      else
        consume(acc, Replies.chain(acc.message, fingerprint, acc.tenant), options)
      end

    finish(acc, profile, fingerprint)
  end

  defp consume(acc, messages, options) do
    # The reducer cannot give its words back when the stream raises, so
    # they are also kept beside it.
    keep(acc)

    messages
    |> AshAi.ToolLoop.stream(options)
    |> Enum.reduce_while(acc, fn event, acc ->
      case stop_asked(acc) do
        # To halt closes the request to the provider: the loop cleans up
        # its stream.
        {true, acc} -> {:halt, %{acc | stopped?: true}}
        {false, acc} -> event |> handle(acc) |> keep() |> go_on()
      end
    end)
  rescue
    # ReqLLM raises out of the stream when the provider answers with an
    # error of HTTP, and when the connection breaks. The loop gives
    # `{:error, _}` only for what it finds itself, such as too many steps.
    error in [ReqLLM.Error.API.Stream] ->
      kept(%{acc | error: error.cause || error})
  end

  # The next request would be longer than the provider takes: it is not
  # sent.
  defp go_on(%{error: :too_long} = acc), do: {:halt, acc}
  defp go_on(acc), do: {:cont, acc}

  defp keep(acc) do
    Process.put(@kept, {acc.text, acc.unfinished, acc.added, acc.parts})
    acc
  end

  defp kept(acc) do
    case Process.delete(@kept) do
      {text, unfinished, added, parts} ->
        %{acc | text: text, unfinished: unfinished, added: added, parts: parts}

      nil ->
        acc
    end
  end

  defp stop_asked(acc) do
    now = now()

    if now - acc.checked_at >= @stop_ms,
      do: {Replies.stop_asked?(acc.message, acc.tenant), %{acc | checked_at: now}},
      else: {false, acc}
  end

  # -- the events of the loop ------------------------------------------------

  defp handle({:content, piece}, acc) when is_binary(piece) and piece != "" do
    save(%{acc | text: acc.text <> piece, unfinished: acc.unfinished <> piece}, false)
  end

  # Each turn of the model and each result of a tool, whole, as the model
  # gets it again in the next request.
  #
  # A turn of the model is the end of a request: the provider counted its
  # prompt, with each tool result so far.
  defp handle({:message, %{role: :assistant} = turn}, acc) do
    parts = acc.parts ++ Transcript.to_parts([turn], reasoning: true)
    save(%{acc | parts: parts, unfinished: "", added: 0}, true)
  end

  # A result of a tool is what the next request adds to the last one. When
  # the two are above the limit of a request, the reply ends here.
  defp handle({:message, turn}, acc) do
    new = Transcript.to_parts([turn], reasoning: true)
    added = acc.added + (new |> Enum.map(&part_bytes/1) |> Enum.sum())
    acc = save(%{acc | parts: acc.parts ++ new, added: added}, true)

    case held(Client.requests(), acc) do
      tokens when is_integer(tokens) and tokens > acc.limit -> %{acc | error: :too_long}
      _fits -> acc
    end
  end

  defp handle({:error, reason}, acc), do: %{acc | error: reason}
  defp handle({:done, result}, acc), do: %{acc | result: result}

  # The call of a tool and its result are in the parts. The result holds
  # raw records, and goes nowhere else.
  defp handle(_event, acc), do: acc

  defp part_bytes(%{"content" => content}) when is_binary(content), do: byte_size(content)
  defp part_bytes(part), do: part |> Jason.encode!() |> byte_size()

  # The tokens that the conversation holds now: the prompt and the answer
  # of the newest request that reported its prompt, and what came after
  # it, at three bytes for a token. `nil` when no request reported one.
  defp held(requests, acc) do
    case requests |> Enum.reverse() |> Enum.find(&(Cost.prompt_tokens(&1.usage) > 0)) do
      nil ->
        nil

      request ->
        Cost.prompt_tokens(request.usage) +
          max(request.usage.output, Replies.tokens(byte_size(acc.unfinished))) +
          Replies.tokens(acc.added)
    end
  end

  defp save(acc, now?) do
    now = now()

    if now? or now - acc.saved_at >= @save_ms do
      Replies.save(acc.reply, acc.text, acc.parts, acc.tenant)
      %{acc | saved_at: now}
    else
      acc
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  # -- how it ended ----------------------------------------------------------

  defp finish(acc, profile, fingerprint) do
    Process.delete(@kept)

    # One record for each request of this reply, the first one first. Also
    # there when the stream raised or the reader left it.
    requests = Client.take_requests()
    last = List.last(requests)
    {state, reason} = ending(acc, last)
    usage = requests |> Enum.map(& &1.usage) |> Cost.sum() |> count_unfinished(last, acc)

    cost = Cost.microdollars(usage, profile.prices)

    log(state, reason)

    Replies.close(
      acc.reply,
      %{
        text: acc.text,
        parts: acc.parts,
        state: state,
        reason: reason,
        model: profile.model,
        usage: usage,
        cost_microdollars: cost,
        prompt_tokens: held(requests, acc),
        prompt_fingerprint: fingerprint
      },
      acc.tenant
    )

    # The use of the month, whatever the end: a reply that failed or that
    # the member stopped is billed too. It has no word in it, and it stays
    # when the conversation is deleted. A reply that sent nothing used
    # nothing.
    if requests != [] do
      Allowance.add!(
        acc.message.owner_id,
        profile.model,
        %{
          replies: 1,
          requests: length(requests),
          input_tokens: usage.input,
          cache_read_tokens: usage.cache_read,
          cache_write_tokens: usage.cache_write,
          output_tokens: usage.output,
          cost_microdollars: cost,
          failed: one(state == :failed and reason != :refused),
          refused: one(reason == :refused),
          stopped: one(state == :stopped)
        },
        acc.tenant
      )
    end

    tell(state, reason, length(requests), usage, cost)
  end

  defp one(true), do: 1
  defp one(false), do: 0

  # For the metrics of the server. The event names no organisation, no
  # member and no model: the use by member is on a page of the
  # organisation, behind its policy.
  defp tell(state, reason, requests, usage, cost) do
    :telemetry.execute(
      [:rescord, :ruby, :reply, :stop],
      %{
        requests: requests,
        input_tokens: usage.input,
        cache_read_tokens: usage.cache_read,
        cache_write_tokens: usage.cache_write,
        output_tokens: usage.output,
        cost_microdollars: cost
      },
      %{state: state, reason: reason}
    )
  end

  defp ending(acc, last) do
    cond do
      acc.stopped? -> {:stopped, nil}
      acc.error == :too_long -> {:failed, :too_long}
      acc.error != nil -> {:failed, Reason.of(acc.error)}
      # The stream ended with no last event. The loop does not do that.
      acc.result == nil -> {:failed, :unknown}
      acc.result.status == :awaiting_approval -> {:awaiting, nil}
      last && last.finish_reason == :content_filter -> {:failed, :refused}
      last && last.finish_reason == :length -> {:complete, :cut}
      true -> {:complete, nil}
    end
  end

  # The provider bills the tokens of an answer that ended early, and does
  # not report them: the report comes at the end of the stream. So the
  # reply counts the words of that request that arrived, at three bytes for
  # a token. The count leaves out the tokens of the thinking, which the
  # reply cannot see.
  defp count_unfinished(usage, %{finish_reason: nil, usage: %{output: reported}}, acc) do
    counted = div(byte_size(acc.unfinished) + 2, 3)
    %{usage | output: usage.output - reported + max(reported, counted)}
  end

  defp count_unfinished(usage, _last, _acc), do: usage

  defp log(:failed, reason) when reason in @errors,
    do: Logger.error("Ruby: a reply failed (#{reason})")

  defp log(:failed, reason), do: Logger.warning("Ruby: a reply failed (#{reason})")
  defp log(_state, _reason), do: :ok
end
