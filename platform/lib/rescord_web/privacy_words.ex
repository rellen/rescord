defmodule RescordWeb.PrivacyWords do
  @moduledoc """
  The words of the requests to erase data and of the settings of privacy
  (ADR 0105).
  """

  alias RescordWeb.Locale

  @doc """
  The days until a request is due, in words.

      iex> RescordWeb.PrivacyWords.days_left(3)
      "3 days left"
      iex> RescordWeb.PrivacyWords.days_left(1)
      "1 day left"
      iex> RescordWeb.PrivacyWords.days_left(0)
      "Due today"
      iex> RescordWeb.PrivacyWords.days_left(-2)
      "2 days overdue"
  """
  @spec days_left(integer) :: String.t()
  def days_left(0), do: "Due today"
  def days_left(days) when days > 0, do: "#{Locale.count(days, "day", "days")} left"
  def days_left(days), do: "#{Locale.count(-days, "day", "days")} overdue"

  @ways [
    own_page: "From their own page",
    email: "By email",
    letter: "By letter",
    in_person: "In person",
    account: "Erasure of the account",
    automatic: "After the months of the settings"
  ]

  @doc "How a request came, in words."
  @spec how(atom) :: String.t()
  def how(way), do: Keyword.fetch!(@ways, way)

  @doc "The ways that a person records a request, for a select."
  @spec way_options() :: [{String.t(), String.t()}]
  def way_options,
    do:
      for(
        {way, words} <- Keyword.take(@ways, [:email, :letter, :in_person]),
        do: {words, to_string(way)}
      )

  @doc "The state of a request, in words, with the kind of its badge."
  @spec state(atom) :: {String.t(), String.t()}
  def state(:received), do: {"Waits", "info"}
  def state(:done), do: {"Erased", "ok"}
  def state(:refused), do: {"Refused", "alert"}
  def state(:withdrawn), do: {"Withdrawn", "info"}
end
