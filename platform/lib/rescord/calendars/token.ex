defmodule Rescord.Calendars.Token do
  @moduledoc """
  The secret in the address of a calendar feed (ADR 0074).

  A token is 32 random bytes, written as 43 characters of an address. A
  calendar app cannot sign in, so the token is the key of the feed: a
  person who has the address reads the feed.

  Rescord stores only `hash/1` of a token, the SHA-256 hash. A copy of the
  database thus opens no feed, and the page can show the address only at
  the time that the feed is made. A token has 256 random bits, so a plain
  hash is enough: nobody can try each token.
  """

  @bytes 32

  @doc "A new token."
  @spec new() :: String.t()
  def new, do: @bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "Whether a text has the shape of a token. A text with another shape names no feed."
  @spec shape?(term) :: boolean
  def shape?(text) when is_binary(text) do
    match?({:ok, <<_::binary-size(@bytes)>>}, Base.url_decode64(text, padding: false))
  end

  def shape?(_other), do: false

  @doc "What Rescord stores of a token: its SHA-256 hash, in hexadecimal."
  @spec hash(String.t()) :: String.t()
  def hash(token) when is_binary(token) do
    :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)
  end
end
