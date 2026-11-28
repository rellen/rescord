defmodule RescordWeb.CalendarWords do
  @moduledoc """
  The words of a calendar feed (ADR 0074): the choices of its tasks, and
  what a feed holds in one line. A page never shows the atom of a value.
  """

  alias RescordWeb.{ResidentWords, TaskWords}

  @tasks [
    mine: "The tasks that name me",
    mine_and_open: "The tasks that name me, and the tasks for anybody",
    all: "Each task",
    none: "No tasks"
  ]

  @doc "The choices of the tasks of a feed as the options of a select: the words, and the value as text."
  @spec tasks_options() :: [{String.t(), String.t()}]
  def tasks_options, do: for({value, words} <- @tasks, do: {words, to_string(value)})

  @doc "The choices that have words, for the test that holds them."
  @spec tasks_choices() :: [atom]
  def tasks_choices, do: Keyword.keys(@tasks)

  @doc "The choice with the text of a field of a form, or `:error`. It makes no atom."
  @spec tasks_of(term) :: {:ok, atom} | :error
  def tasks_of(text) when is_binary(text) do
    case Enum.find(@tasks, fn {value, _words} -> Atom.to_string(value) == text end) do
      {value, _words} -> {:ok, value}
      nil -> :error
    end
  end

  def tasks_of(_other), do: :error

  @doc """
  What a feed holds, as a list of words: `["The tasks that name me",
  "the expiry dates of the stock"]`. A page joins them.
  """
  @spec parts(map) :: [String.t()]
  def parts(feed) do
    Enum.reject(
      [
        feed.tasks != :none && Keyword.fetch!(@tasks, feed.tasks),
        feed.with_returns && "The days that residents are expected back",
        feed.with_expiry && "The expiry dates of the stock",
        feed.with_notes && "With the notes that people wrote"
      ],
      &(&1 in [false, nil])
    )
  end

  @doc """
  When a calendar app last read a feed, in the time of the organisation:
  `Last read on 28 November 2026 at 15:04`, or words for a feed that no
  app read yet. `local` is the instant as the organisation has it.
  """
  @spec last_read(DateTime.t() | nil) :: String.t()
  def last_read(nil), do: "No calendar app read it yet"

  def last_read(%DateTime{} = local) do
    "Last read on #{ResidentWords.date(DateTime.to_date(local))} at #{TaskWords.time(local)}"
  end
end
