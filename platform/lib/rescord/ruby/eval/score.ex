defmodule Rescord.Ruby.Eval.Score do
  @moduledoc """
  Scores one answer of the evaluation set of Ruby against its case, by
  code. Each check is true or false, and an answer passes when each is
  true.

    * `:state` - the reply is complete. A reply that failed, that the
      provider refused or that the limit of tokens cut fails;
    * `:calls` - each tool of `must_call` was called;
    * `:no_extra_calls` - no tool of `must_not_call` was called;
    * `:links` - the answer has the id of each record of `must_link`;
    * `:references` - each id in the answer is in a tool result of the
      reply. Ruby writes no reference that no tool gave;
    * `:numbers` - each number in the answer is in a tool result, in the
      question or in its header. A whole number up to 12 with no unit
      passes: a count of tasks, an hour of a clock;
    * `:says` and `:does_not_say` - the patterns of the case;
    * `:form` - no heading, no table, and not more words than the case
      takes;
    * `:limits` - the requests and the seconds of the reply.

  The checks see words and not meaning. They miss a wrong claim in right
  words, and a person reads the failed answers. A judge model is not here.
  """

  alias Rescord.Ruby.Eval.Case

  @typedoc """
  An answer, as `Rescord.Ruby.Eval.ask/3` gives it: the state and the
  reason of the reply, its text, the names of the tools it called, the
  text of each tool result, what the member sent (the header and each
  question), and the counts.
  """
  @type answer :: %{
          state: atom,
          reason: atom | nil,
          text: String.t(),
          calls: [String.t()],
          results: [String.t()],
          asked: String.t(),
          requests: non_neg_integer,
          usage: map,
          cost_microdollars: non_neg_integer,
          seconds: float
        }

  @checks [
    :state,
    :calls,
    :no_extra_calls,
    :links,
    :references,
    :numbers,
    :says,
    :does_not_say,
    :form,
    :limits
  ]

  @doc "Each check, in the order of a report."
  @spec checks() :: [atom]
  def checks, do: @checks

  @doc "The checks that this answer fails. An empty list for an answer that passes."
  @spec failed(Case.t(), answer) :: [atom]
  def failed(%Case{} = test, answer), do: Enum.reject(@checks, &check(&1, test, answer))

  defp check(:state, _test, answer), do: answer.state == :complete and is_nil(answer.reason)
  defp check(:calls, test, answer), do: Enum.all?(test.must_call, &(&1 in answer.calls))

  defp check(:no_extra_calls, test, answer),
    do: not Enum.any?(test.must_not_call, &(&1 in answer.calls))

  defp check(:links, test, answer),
    do: Enum.all?(test.must_link, &String.contains?(answer.text, &1))

  defp check(:references, _test, answer) do
    given = Enum.join(answer.results, "\n")

    uuid()
    |> Regex.scan(answer.text)
    |> Enum.all?(fn [id] -> String.contains?(given, id) end)
  end

  defp check(:numbers, _test, answer) do
    known = MapSet.new(numbers(Enum.join([answer.asked | answer.results], "\n")))

    answer.text
    |> prose()
    |> stated()
    |> Enum.all?(fn {number, unit?} ->
      MapSet.member?(known, number) or (not unit? and small?(number))
    end)
  end

  defp check(:says, test, answer), do: Enum.all?(test.must_say, &Regex.match?(&1, answer.text))

  defp check(:does_not_say, test, answer),
    do: not Enum.any?(test.must_not_say, &Regex.match?(&1, answer.text))

  defp check(:form, test, answer) do
    text = answer.text
    words = text |> prose() |> String.split() |> length()

    not Regex.match?(~r/^\s{0,3}\#{1,6}\s/m, text) and
      not Regex.match?(~r/^\s*\|.+\|\s*$/m, text) and
      words <= test.max_words
  end

  defp check(:limits, test, answer),
    do: answer.requests <= test.max_requests and answer.seconds <= test.max_seconds

  defp uuid, do: ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i

  # The text that a member reads: with no target of a link, and no id.
  defp prose(text) do
    text = Regex.replace(~r/\]\([^)\s]*\)/, text, "]")
    Regex.replace(uuid(), text, " ")
  end

  # Each number of a text, in one form: 08 is 8, and 0.50 is 0.5.
  defp numbers(text) do
    text = Regex.replace(uuid(), text, " ")
    for [number] <- Regex.scan(~r/\d+(?:\.\d+)?/, text), do: canonical(number)
  end

  # Each number that an answer states, and whether a unit of a dose or of
  # a weight follows it.
  defp stated(text) do
    for [_all, number | unit] <-
          Regex.scan(~r/(\d+(?:\.\d+)?)(?:\s?(ml|mg|kg|g|kilos?|grams?)\b|\s?(%))?/i, text) do
      {canonical(number), Enum.any?(unit, &(&1 != ""))}
    end
  end

  defp canonical(number) do
    case Float.parse(number) do
      {value, ""} when value == trunc(value) -> Integer.to_string(trunc(value))
      {value, ""} -> :erlang.float_to_binary(value, [:short])
    end
  end

  defp small?(number) do
    case Integer.parse(number) do
      {value, ""} -> value <= 12
      _not_whole -> false
    end
  end
end
