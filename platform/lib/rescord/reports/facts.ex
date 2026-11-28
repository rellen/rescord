defmodule Rescord.Reports.Facts do
  @moduledoc """
  The facts of a report (ADR 0076): what its module reads through the
  domains, as the person who asks.

  A module of a report has `read/3`. It gets the arguments of the action,
  the options of each read, which are the actor and the organisation, and
  the instant of the request. It returns a map of records, dates and values.
  The key `:files`, when it is there, is a map from a path to the bytes of a
  file that the template shows: a photo.

  Each read here passes the options as they are, and never
  `authorize?: false`: a record that the person cannot read is not in the
  report.
  """

  alias Rescord.Reports.Facts

  @doc "Reads the facts of a report."
  @callback read(arguments :: map, options :: keyword, now :: DateTime.t()) ::
              {:ok, map} | {:error, term}

  @modules %{
    resident_record: Facts.ResidentRecord,
    cage_card: Facts.CageCard,
    register: Facts.Register,
    movements: Facts.Movements,
    task_sheet: Facts.TaskSheet,
    stock: Facts.Stock,
    housing: Facts.Housing,
    expenses: Facts.Expenses
  }

  @doc "The facts of `report`, or the error of the read that failed."
  @spec read(atom, map, keyword, DateTime.t()) :: {:ok, map} | {:error, term}
  def read(report, arguments, options, now),
    do: Map.fetch!(@modules, report).read(arguments, options, now)

  @doc """
  The day of a report: the one that the person gave, or today in the
  organisation. `{:error, error}` for a day after today when `past_only?`
  is true.
  """
  @spec day(Date.t() | nil, keyword, DateTime.t(), keyword) :: {:ok, Date.t()} | {:error, term}
  def day(given, options, now, checks \\ []) do
    today = Rescord.Accounts.local_date(options[:tenant], now)

    cond do
      is_nil(given) ->
        {:ok, today}

      checks[:past_only?] && Date.compare(given, today) == :gt ->
        {:error, invalid(checks[:field] || :on, "is after today")}

      true ->
        {:ok, given}
    end
  end

  @doc "An error of an argument, with words for a person."
  @spec invalid(atom, String.t()) :: Exception.t()
  def invalid(field, message),
    do: Ash.Error.Action.InvalidArgument.exception(field: field, message: message)

  @doc """
  The option that reads the records as they stood at the end of a past day
  in the organisation (ADR 0012): `[as_of: instant]`. For today, and for a
  day after it, the list is empty, and a read gives the records of now.
  """
  @spec past(Date.t(), keyword, DateTime.t()) :: keyword
  def past(%Date{} = date, options, now) do
    {_start, next} = Rescord.Accounts.day_range(options[:tenant], date)

    if DateTime.compare(next, now) == :gt,
      do: [],
      else: [as_of: DateTime.add(next, -1, :microsecond)]
  end
end
