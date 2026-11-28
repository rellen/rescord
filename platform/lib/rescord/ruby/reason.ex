defmodule Rescord.Ruby.Reason do
  @moduledoc """
  Why a request to a provider failed, as one of a short list of atoms
  (ADR 0069). A reply that failed keeps its reason, and the button "Test"
  of a provider keeps one too, so that a page says the same sentence for
  both.

  The reason is all that leaves the place of a failure. The error itself
  can hold the body of a request and the answer of the service, so it never
  goes to a log, to a record or to a page.
  """

  @reasons [
    :provider_busy,
    :provider_down,
    :request_refused,
    :key_refused,
    :provider_limit,
    :refused,
    :cut,
    :too_many_steps,
    :allowance,
    :rate,
    :too_long,
    :unknown
  ]

  @type t ::
          :provider_busy
          | :provider_down
          | :request_refused
          | :key_refused
          | :provider_limit
          | :refused
          | :cut
          | :too_many_steps
          | :allowance
          | :rate
          | :too_long
          | :unknown

  @doc "Each reason."
  @spec all() :: [t]
  def all, do: @reasons

  @doc "The reason of an error of the library that reaches the provider, or of the loop."
  @spec of(term) :: t
  def of(:max_iterations_reached), do: :too_many_steps
  def of(%{status: status}) when status in [401, 403], do: :key_refused
  def of(%{status: status}) when status in [429, 529], do: :provider_busy
  def of(%{status: status}) when is_integer(status) and status >= 500, do: :provider_down

  # Anthropic answers 400 when the account is past the limit of spend that
  # its owner set. The words are the only sign.
  def of(%{status: 400, reason: reason}) when is_binary(reason) do
    if reason =~ "usage limits", do: :provider_limit, else: :request_refused
  end

  def of(%{status: 400}), do: :request_refused
  # No such model at the service, most often.
  def of(%{status: 404}), do: :request_refused
  # No connection, or a connection that broke.
  def of(%module{})
      when module in [Finch.TransportError, Req.TransportError, Mint.TransportError],
      do: :provider_down

  def of(:timeout), do: :provider_down
  def of(_other), do: :unknown

  @doc """
  How the stream of a reply ended, as the state and the reason: from the
  error of the stream (`nil` for none), the last event of the loop (`nil`
  when the stream gave none), and the record of the last request
  (`Rescord.Ruby.LLM.Client`), which says why the model stopped.

  A reply and a run of the evaluation set both ask here, so the two never
  name one end in two ways. A stop by the member is not here: the caller
  knows it.
  """
  @spec ending(term, term, map | nil) :: {:complete | :failed | :awaiting, t | nil}
  def ending(:too_long, _result, _last), do: {:failed, :too_long}
  def ending(error, _result, _last) when not is_nil(error), do: {:failed, of(error)}
  # The stream ended with no last event. The loop does not do that.
  def ending(nil, nil, _last), do: {:failed, :unknown}
  def ending(nil, %{status: :awaiting_approval}, _last), do: {:awaiting, nil}
  def ending(nil, _result, %{finish_reason: :content_filter}), do: {:failed, :refused}
  def ending(nil, _result, %{finish_reason: :length}), do: {:complete, :cut}
  def ending(nil, _result, _last), do: {:complete, nil}
end
