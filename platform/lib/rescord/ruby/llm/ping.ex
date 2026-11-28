defmodule Rescord.Ruby.LLM.Ping do
  @moduledoc """
  The button "Test" of the page of a provider: one small request, with the
  options of a reply, so that it proves what a reply needs: the key, the
  model, the address and the stream.

  The request holds the word "ping" and nothing of a rescue: no system
  prompt, no tools and no record. It asks for an answer of at most 64
  tokens, and throws the answer away. For an older model of Claude, which
  thinks with a budget of tokens, ReqLLM raises that limit to a little
  above the budget.

  The result is `:ok`, or a reason of `Rescord.Ruby.Reason`, so that the
  page says the same sentence for a test as a member reads for a reply.
  """

  alias Rescord.Ruby.LLM.{Client, Cost, Profile}
  alias Rescord.Ruby.Reason

  @type result :: %{
          outcome: :ok | {:error, Reason.t()},
          cost_microdollars: non_neg_integer
        }

  @doc "Sends the request, and says how it ended and what it cost."
  @spec run(Profile.t()) :: result
  def run(%Profile{} = profile) do
    outcome = send_one(profile)

    cost =
      Client.take_requests()
      |> Enum.map(& &1.usage)
      |> Cost.sum()
      |> Cost.microdollars(profile.prices)

    %{outcome: outcome, cost_microdollars: cost}
  end

  defp send_one(profile) do
    opts = Keyword.put(Profile.req_llm_opts(profile), :max_tokens, 64)

    case Client.stream_text(Profile.model_spec(profile), [ReqLLM.Context.user("ping")], opts) do
      {:ok, response} ->
        Stream.run(response.stream)
        :ok

      {:error, error} ->
        {:error, Reason.of(error)}
    end
  rescue
    # As in a reply: ReqLLM raises an error of HTTP out of the stream.
    error in [ReqLLM.Error.API.Stream] -> {:error, Reason.of(error.cause || error)}
    # Nothing of another fault goes further than its kind.
    _error -> {:error, :unknown}
  end
end
