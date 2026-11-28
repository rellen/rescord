defmodule RescordWeb.RubyWords do
  @moduledoc """
  The words of the assistant, Ruby (ADR 0069): the services of a provider,
  its key as a page may say it, what a test found, and the amounts of
  money of its form.

  A page of a root user has no organisation and so no time zone: a day and
  a time here are in UTC, and a time says so.
  """

  @services [
    anthropic: "Anthropic",
    bedrock: "Amazon Bedrock",
    ollama: "Ollama",
    openai_compatible: "An OpenAI-compatible service"
  ]

  @efforts [low: "Low", medium: "Medium", high: "High"]

  @doc "The services of a provider, each with its words, in order."
  def services, do: @services

  @doc "The words of a service."
  def service(kind), do: Keyword.fetch!(@services, kind)

  @doc "The service with the text of a path or of a field, or `:error`. It makes no atom."
  def service_of(text) when is_binary(text) do
    case Enum.find(@services, fn {kind, _words} -> Atom.to_string(kind) == text end) do
      {kind, _words} -> {:ok, kind}
      nil -> :error
    end
  end

  def service_of(_other), do: :error

  @doc "What each service is, in a sentence for the person who chooses."
  def about(:anthropic),
    do: "Claude, at Anthropic. The records of a question go to Anthropic."

  def about(:bedrock),
    do: "Claude, at Amazon Web Services, in the region that you name."

  def about(:ollama),
    do:
      "A model on a machine of your own. Ruby only reads with this service: it proposes no record."

  def about(:openai_compatible),
    do:
      "A server that speaks the chat API of OpenAI, such as llama.cpp or vLLM. " <>
        "Ruby only reads with this service: it proposes no record."

  @doc "The efforts, as the options of a select."
  def efforts, do: for({effort, words} <- @efforts, do: {words, Atom.to_string(effort)})

  @doc "A day, such as 3 March 2026, in UTC."
  def day(%DateTime{} = instant), do: Calendar.strftime(instant, "%-d %B %Y")

  @doc "A day and a time, such as 28 November 2026 at 09:14 UTC."
  def time(%DateTime{} = instant), do: Calendar.strftime(instant, "%-d %B %Y at %H:%M UTC")

  @doc "The key of a provider, as the list says it. It is never the key."
  def key(%{kind: :ollama}), do: "Takes no key"
  def key(%{key_set_at: nil}), do: "No key"
  def key(%{key_hint: nil, key_set_at: set_at}), do: "Set on #{day(set_at)}"
  def key(%{key_hint: hint, key_set_at: set_at}), do: "Ends in #{hint}, set on #{day(set_at)}"

  @doc """
  The words below the key field. `provider` is `nil` for a new provider.
  `retype?` says that the person typed a key that the page did not keep.
  """
  def key_hint(provider, kind, retype?) do
    stored =
      case provider do
        nil ->
          "Rescord keeps the key encrypted, and no page shows it again."

        %{key_set_at: nil} ->
          "This provider has no key. Rescord keeps a key encrypted, and no page shows it again."

        %{key_hint: nil, key_set_at: set_at} ->
          "The key was set on #{day(set_at)}. Leave the field empty to keep it. " <>
            "A new key takes its place: then revoke the old one at the service."

        %{key_hint: hint, key_set_at: set_at} ->
          "The key ends in #{hint} and was set on #{day(set_at)}. Leave the field empty to keep it. " <>
            "A new key takes its place: then revoke the old one at the service."
      end

    optional =
      if kind == :openai_compatible and (provider == nil or provider.key_set_at == nil),
        do: " Leave the field empty for a server that asks for no key.",
        else: ""

    again = if retype?, do: " Type it again: Rescord did not keep what you typed.", else: ""

    stored <> optional <> again
  end

  @doc "What the last test of a provider found: the kind of the state, and a word."
  def test_state(%{tested_at: nil}), do: {"none", "Not tested"}
  def test_state(%{test_result: :ok}), do: {"ok", "Answered"}
  def test_state(_failed), do: {"alert", "Failed"}

  @doc """
  Why a test failed, and what to do, for the root user. Each reason of
  `Rescord.Ruby.Reason` has a sentence.
  """
  def failure(:key_refused),
    do:
      "the service refused the key, or Rescord could not open the key that it keeps. " <>
        "Type the key again below, or make a new one at the service."

  def failure(:provider_down),
    do: "the service did not answer. Check the address, and the network of this server."

  def failure(:provider_busy), do: "the service is busy. Try again in a minute."

  def failure(:provider_limit),
    do: "the account is at the spend limit that its owner set at the service."

  def failure(:request_refused),
    do: "the service refused the request. Check the name of the model."

  def failure(:refused), do: "the model refused to answer the test."
  def failure(:cut), do: "the answer of the test was cut short."
  def failure(:too_many_steps), do: "the test took too many steps."
  def failure(:allowance), do: "the allowance of the month is used."
  def failure(:rate), do: "there were too many requests. Wait a moment."
  def failure(:too_long), do: "the request was too long for the model."

  def failure(:unknown),
    do: "something went wrong that Rescord cannot name. Try again, and then check each field."

  @doc "Whole US cents as US dollars, for a field: `2000` is `20`, and `1250` is `12.50`."
  def dollars(nil), do: ""
  def dollars(cents) when is_integer(cents) and rem(cents, 100) == 0, do: "#{div(cents, 100)}"

  def dollars(cents) when is_integer(cents),
    do:
      "#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  @doc """
  Millionths of a US dollar as US dollars, for a field: the price of a
  million tokens `4000000` is `4`, and `100000` is `0.1`.
  """
  def price(nil), do: ""

  def price(millionths) when is_integer(millionths) do
    millionths
    |> Decimal.new()
    |> Decimal.div(1_000_000)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  @doc "The whole US cents of an amount of US dollars that a person typed, or `:error`."
  def cents(text), do: scaled(text, 100)

  @doc "The millionths of a US dollar of an amount that a person typed, or `:error`."
  def millionths(text), do: scaled(text, 1_000_000)

  # An amount with more digits than the unit holds is refused, and not
  # rounded: the person sees what Rescord keeps.
  defp scaled(text, unit) when is_binary(text) do
    with {%Decimal{coef: digits} = amount, ""} when is_integer(digits) <-
           Decimal.parse(String.trim(text)),
         false <- Decimal.negative?(amount),
         scaled = Decimal.mult(amount, unit),
         true <- Decimal.integer?(scaled),
         true <- Decimal.compare(scaled, 1_000_000_000) != :gt do
      {:ok, Decimal.to_integer(scaled)}
    else
      _other -> :error
    end
  end

  defp scaled(_other, _unit), do: :error
end
