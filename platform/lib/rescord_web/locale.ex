defmodule RescordWeb.Locale do
  @moduledoc """
  The forms of a date, a time of day and a number in the locale of an
  organisation (ADR 0075): `16 November 2026` in Australia, and
  `November 16, 2026` in the United States.

  This is the one module that calls `Localize`. A page calls the words
  modules, such as `RescordWeb.ResidentWords.date/1`, and they call this
  one.

  ## The locale of a page

  `put/1` sets the locale of the process, and the hook
  `:require_organisation` of `RescordWeb.UserAuth` calls it with the
  organisation of the page. `current/0` reads it. A process with no locale,
  such as a page with no organisation, or a test of a words module, has the
  default of `Rescord.Accounts.default_locale/0`.

  The locale of a process does not reach a task that the process starts.
  Give such a task the tag of `current/0`, and call `put/1` in it.

  Each function gives `Localize` the locale by name. The default locale of
  `Localize` itself can come from the variable `LANG` of the server, so no
  function here relies on it.

  ## The forms

  A function writes the ISO form, or the plain digits, when `Localize`
  cannot write the form of the locale, and logs a warning: a page does not
  fail for a form.
  """

  require Logger

  alias Rescord.Accounts

  @key {__MODULE__, :locale}

  @doc """
  Sets the locale of this process: an organisation, or a tag such as
  `en-US`. A tag that Rescord does not offer sets the default.
  """
  @spec put(%{locale: String.t()} | String.t() | nil) :: :ok
  def put(%{locale: tag}), do: put(tag)

  def put(tag) do
    if Accounts.locale?(tag), do: Process.put(@key, tag), else: Process.delete(@key)
    :ok
  end

  @doc "The tag of the locale of this process, for example `en-AU`."
  @spec current() :: String.t()
  def current, do: Process.get(@key) || Accounts.default_locale()

  @doc """
  A date in words.

      iex> RescordWeb.Locale.date(~D[2026-11-16])
      "16 November 2026"
  """
  @spec date(Date.t()) :: String.t()
  def date(%Date{} = date) do
    case Localize.Date.to_string(date, locale: current(), format: :long) do
      {:ok, words} -> words
      {:error, reason} -> plain(Date.to_iso8601(date), reason)
    end
  end

  @doc """
  A date in words, with its day of the week.

      iex> RescordWeb.Locale.day(~D[2026-11-16])
      "Monday, 16 November 2026"
  """
  @spec day(Date.t()) :: String.t()
  def day(%Date{} = date) do
    case Localize.Date.to_string(date, locale: current(), format: :full) do
      {:ok, words} -> words
      {:error, reason} -> plain(Date.to_iso8601(date), reason)
    end
  end

  @doc """
  A month in words, from a day of it: the month and the year.

      iex> RescordWeb.Locale.month(~D[2026-11-01])
      "November 2026"
  """
  @spec month(Date.t()) :: String.t()
  def month(%Date{} = date) do
    case Localize.Date.to_string(date, locale: current(), format: :yMMMM) do
      {:ok, words} -> words
      {:error, reason} -> plain(Calendar.strftime(date, "%Y-%m"), reason)
    end
  end

  @doc """
  The short name of the month of a date, for the head of a narrow column.

      iex> RescordWeb.Locale.short_month(~D[2026-12-01])
      "Dec"
  """
  @spec short_month(Date.t()) :: String.t()
  def short_month(%Date{} = date), do: formatted(date, :MMM, "%b")

  @doc """
  A short date with no year, for the head of a narrow row.

      iex> RescordWeb.Locale.short_date(~D[2026-11-30])
      "30 Nov"
  """
  @spec short_date(Date.t()) :: String.t()
  def short_date(%Date{} = date), do: formatted(date, :MMMd, "%d %b")

  @doc """
  The day of the week of a date, in full or short.

      iex> RescordWeb.Locale.weekday(~D[2026-12-01])
      "Tuesday"

      iex> RescordWeb.Locale.weekday(~D[2026-12-01], :short)
      "Tue"
  """
  @spec weekday(Date.t(), :long | :short) :: String.t()
  def weekday(date, length \\ :long)
  def weekday(%Date{} = date, :long), do: formatted(date, :EEEE, "%A")
  def weekday(%Date{} = date, :short), do: formatted(date, :E, "%a")

  defp formatted(date, format, fallback) do
    case Localize.Date.to_string(date, locale: current(), format: format) do
      {:ok, words} -> words
      {:error, reason} -> plain(Calendar.strftime(date, fallback), reason)
    end
  end

  @doc """
  A time of day, to the minute. A date and time gives its time of day as it
  is: turn an instant into the local time of the organisation first.

  The data of CLDR has a narrow no-break space (U+202F) before `am`. This
  writes a usual space there, so a search of the page finds `8:30 am`.

      iex> RescordWeb.Locale.time(~T[08:30:00])
      "8:30 am"

      iex> RescordWeb.Locale.time(~T[18:05:00])
      "6:05 pm"
  """
  @spec time(Time.t() | DateTime.t() | NaiveDateTime.t()) :: String.t()
  def time(%Time{} = time) do
    case Localize.Time.to_string(time, locale: current(), format: :short) do
      {:ok, words} -> String.replace(words, " ", " ")
      {:error, reason} -> plain(Calendar.strftime(time, "%H:%M"), reason)
    end
  end

  def time(%DateTime{} = local), do: local |> DateTime.to_time() |> time()
  def time(%NaiveDateTime{} = local), do: local |> NaiveDateTime.to_time() |> time()

  @doc """
  A local date and time in words: the date, a comma, and the time of day.

      iex> RescordWeb.Locale.date_time(~N[2026-11-16 08:30:00])
      "16 November 2026, 8:30 am"
  """
  @spec date_time(DateTime.t() | NaiveDateTime.t()) :: String.t()
  def date_time(%DateTime{} = local), do: "#{date(DateTime.to_date(local))}, #{time(local)}"

  def date_time(%NaiveDateTime{} = local),
    do: "#{date(NaiveDateTime.to_date(local))}, #{time(local)}"

  @doc """
  A number with the marks of the locale, each digit of it, and no zeros at
  the end. It never rounds: a dose of `0.00025` stays `0.00025`.

      iex> RescordWeb.Locale.number(Decimal.new("1095.50"))
      "1,095.5"

      iex> RescordWeb.Locale.number(Decimal.new("0.00025"))
      "0.00025"

      iex> RescordWeb.Locale.number(1234567)
      "1,234,567"
  """
  @spec number(Decimal.t() | integer) :: String.t()
  def number(%Decimal{} = value) do
    value = Decimal.normalize(value)

    # The default pattern of a locale keeps three digits after the point and
    # rounds the rest away. The count of the digits of the value itself keeps
    # each one.
    with %Decimal{coef: coef, exp: exp} when is_integer(coef) <- value,
         {:ok, words} <-
           Localize.Number.to_string(value, locale: current(), fractional_digits: max(0, -exp)) do
      words
    else
      {:error, reason} -> plain(Decimal.to_string(value, :normal), reason)
      # Not a number, or an infinity: there is no form for it.
      %Decimal{} -> Decimal.to_string(value, :normal)
    end
  end

  def number(value) when is_integer(value) do
    case Localize.Number.to_string(value, locale: current()) do
      {:ok, words} -> words
      {:error, reason} -> plain(Integer.to_string(value), reason)
    end
  end

  @doc """
  A count with the word for one or the word for more than one: `1 day`,
  `0 days`, `1,200 days`. A page gives both words whole, and never adds an
  `s` to a word: a plural that is a word of its own moves to Gettext with
  the sentence when a second language comes (ADR 0075).

      iex> RescordWeb.Locale.count(1, "day", "days")
      "1 day"

      iex> RescordWeb.Locale.count(1200, "entry", "entries")
      "1,200 entries"
  """
  @spec count(integer, String.t(), String.t()) :: String.t()
  def count(1, one, _many), do: "1 #{one}"
  def count(number, _one, many) when is_integer(number), do: "#{number(number)} #{many}"

  @doc """
  Words joined as a list, with the pattern of the locale: `Biscuit and
  Clover`, `Biscuit, Clover and Pip`. A page never joins words with `", "`
  and `" and "` by hand (ADR 0108).

      iex> RescordWeb.Locale.list(["Biscuit", "Clover"])
      "Biscuit and Clover"
  """
  @spec list([String.t()]) :: String.t()
  def list(words) when is_list(words) do
    case Localize.List.to_string(words, locale: current()) do
      {:ok, joined} -> joined
      {:error, reason} -> plain(Enum.join(words, ", "), reason)
    end
  end

  @doc """
  An amount of money, with the sign or the code of its currency as the
  locale writes it (ADR 0082).

      iex> RescordWeb.Locale.money(Money.new(:AUD, "1234.5"))
      "$1,234.50"
  """
  @spec money(Money.t()) :: String.t()
  def money(%Money{} = money) do
    case Money.to_string(money, locale: current()) do
      {:ok, words} ->
        words

      {:error, reason} ->
        plain("#{Decimal.to_string(money.amount, :normal)} #{money.currency}", reason)
    end
  end

  @doc """
  The name of a currency, or its code when the locale has no name for it.

      iex> RescordWeb.Locale.currency_name("AUD")
      "Australian Dollar"
  """
  @spec currency_name(String.t() | atom) :: String.t()
  def currency_name(code) do
    case Localize.Currency.display_name(code, locale: current()) do
      {:ok, name} -> name
      {:error, _no_name} -> to_string(code)
    end
  end

  @doc """
  The name of a currency for more than one of it, or its code.

      iex> RescordWeb.Locale.currency_plural("AUD")
      "Australian dollars"
  """
  @spec currency_plural(String.t() | atom) :: String.t()
  def currency_plural(code) do
    case Localize.Currency.pluralize(2, code, locale: current()) do
      {:ok, name} -> name
      {:error, _no_name} -> to_string(code)
    end
  end

  defp plain(text, reason) do
    Logger.warning(
      "no form of the locale #{current()} for #{text}: #{Rescord.Log.reason(reason)}"
    )

    text
  end
end
