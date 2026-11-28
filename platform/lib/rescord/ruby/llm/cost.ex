defmodule Rescord.Ruby.LLM.Cost do
  @moduledoc """
  The price of the tokens of a turn, in millionths of a US dollar.

  Rescord keeps its own table of prices, for two reasons. ReqLLM gives no
  price for a stream that Ruby reads through `AshAi.ToolLoop` (the usage has
  `pricing: %{status: :unknown}`). And the catalogue of ReqLLM has one
  price for a write to the prompt cache, the price of the cache of five
  minutes, while Ruby uses the cache of one hour, which costs more.

  A price is in millionths of a dollar for one million tokens. So one token
  at the price 4_000_000 costs 4 millionths of a dollar, and the arithmetic
  is in integers.
  """

  # {input, output, cache read, cache write of one hour}, for one million
  # tokens. Source: the prices that Anthropic published for its own API, as
  # they stood on 3 November 2026: the input and the output of each model,
  # and the cache read of Opus and Sonnet (0.05 times the input). Two values
  # here are the usual ratios and were not read from a price list: the cache
  # read of Haiku (0.1 times the input), and the write of one hour (2 times
  # the input). The prices of Haiku are those of a prompt up to 100,000
  # tokens, and a request of Ruby is below that. The bill of the provider is
  # the truth, and each page says "about" beside a sum.
  @prices %{
    "claude-opus-5-5" => {4_000_000, 20_000_000, 200_000, 8_000_000},
    "claude-sonnet-5-5" => {2_000_000, 10_000_000, 100_000, 4_000_000},
    "claude-haiku-5-5" => {100_000, 500_000, 10_000, 200_000}
  }

  @type prices :: {non_neg_integer, non_neg_integer, non_neg_integer, non_neg_integer}

  @typedoc "The tokens of one request or of some requests, by what each costs."
  @type usage :: %{
          input: non_neg_integer,
          cache_read: non_neg_integer,
          cache_write: non_neg_integer,
          output: non_neg_integer
        }

  @doc """
  The prices of a model, or `nil` for a model that the table does not have.

  A model of Claude on Amazon Bedrock has the name of Anthropic inside its
  own, such as `au.anthropic.claude-sonnet-5-5`. It has the prices of the
  table. A profile of a geography (`au.`, `eu.`, `us.`) costs a tenth more,
  and `global.` does not.
  """
  @spec prices(String.t()) :: prices | nil
  def prices(model) when is_binary(model) do
    case Map.fetch(@prices, model) do
      {:ok, prices} -> prices
      :error -> bedrock(model)
    end
  end

  defp bedrock(model) do
    with [_all, geography, name] <- Regex.run(~r/^(?:([a-z]+)\.)?anthropic\.(claude-.+)$/, model),
         {_name, {input, output, read, write}} <-
           Enum.find(@prices, fn {known, _prices} -> String.starts_with?(name, known) end) do
      if geography in ["", "global"] do
        {input, output, read, write}
      else
        {div(input * 11, 10), div(output * 11, 10), div(read * 11, 10), div(write * 11, 10)}
      end
    else
      _no_match -> nil
    end
  end

  @doc """
  The cost of the tokens, in millionths of a dollar, rounded up.

  A model with no price (a model on the rescue's own machine) costs 0.
  """
  @spec microdollars(usage(), prices | nil) :: non_neg_integer
  def microdollars(_usage, nil), do: 0

  def microdollars(usage, {input, output, cache_read, cache_write}) do
    total =
      usage.input * input + usage.cache_read * cache_read +
        usage.cache_write * cache_write + usage.output * output

    div(total + 999_999, 1_000_000)
  end

  @doc "The sum of the tokens of some requests."
  @spec sum([usage()]) :: usage()
  def sum(usages) do
    Enum.reduce(usages, %{input: 0, cache_read: 0, cache_write: 0, output: 0}, fn usage, acc ->
      Map.merge(acc, usage, fn _key, a, b -> a + b end)
    end)
  end

  @doc "The size of the prompt of a request, in tokens."
  @spec prompt_tokens(usage()) :: non_neg_integer
  def prompt_tokens(usage), do: usage.input + usage.cache_read + usage.cache_write
end
