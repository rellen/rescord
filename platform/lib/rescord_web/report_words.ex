defmodule RescordWeb.ReportWords do
  @moduledoc """
  The words of the reports (ADR 0076): this module turns the facts that
  `Rescord.Reports.Facts` read into the data of a template of `priv/typst`.

  The configuration names this module as `:report_wording`, because the
  core does not call the web layer, and the words of Rescord are here
  (`RescordWeb.ResidentWords` and the others). A report thus says a thing
  as the pages say it.

  The data of a template is maps, lists and text that is ready to show. A
  template lays it out, and decides nothing. A value that is not there is
  `nil`, and never an empty text, so a template asks `!= none`.

  Each report has a module under `RescordWeb.ReportWords`, with `data/1`.
  Each one puts the frame of the document under `:frame`: see `frame/3`.
  """

  @behaviour Rescord.Reports.Wording

  alias Rescord.Accounts
  alias RescordWeb.{JournalWords, Locale, ReportWords, ResidentWords}

  @modules %{
    resident_record: ReportWords.ResidentRecord,
    cage_card: ReportWords.CageCard,
    register: ReportWords.Register,
    movements: ReportWords.Movements,
    task_sheet: ReportWords.TaskSheet,
    stock: ReportWords.Stock,
    housing: ReportWords.Housing,
    expenses: ReportWords.Expenses
  }

  @doc """
  The data of a report. Each date, time of day and number has the form of
  the locale of the organisation of the facts (ADR 0075): the caller can be
  a process with no locale, such as a request to a controller, so this
  function sets the locale for the words, and then puts back the one that
  the process had.
  """
  @impl true
  def data(report, facts) do
    before = Locale.current()
    Locale.put(facts.organisation)

    try do
      Map.fetch!(@modules, report).data(facts)
    after
      Locale.put(before)
    end
  end

  @doc "The reports that have words, for the test that holds them to the actions."
  def reports, do: Map.keys(@modules)

  @doc """
  The frame of a document: the name of the organisation, the title, a line
  below the title or `nil`, when the report was made in the time zone of the
  organisation, that time as the date of the document, and the paper of the
  document as Typst names it (ADR 0093).
  """
  def frame(facts, title, subtitle \\ nil) do
    local = Accounts.local_time(facts.organisation, facts.made_at)

    %{
      organisation: facts.organisation.name,
      title: title,
      subtitle: subtitle,
      made: "Made on #{JournalWords.time(local)}",
      date: DateTime.to_naive(local),
      paper: typst_paper(facts.paper)
    }
  end

  # The name that Typst has for a paper.
  defp typst_paper(:a4), do: "a4"
  defp typst_paper(:us_letter), do: "us-letter"

  @doc """
  The name of a paper of a report (ADR 0093).

      iex> RescordWeb.ReportWords.paper_name(:us_letter)
      "US Letter"
  """
  def paper_name(:a4), do: "A4"
  def paper_name(:us_letter), do: "US Letter"

  @doc "The papers of a report as the options of a select: the name, and the value of a form."
  def paper_options do
    for paper <- Accounts.paper_sizes(), do: {paper_name(paper), Atom.to_string(paper)}
  end

  @doc "A text, or `nil` for an empty one and for none."
  def text(nil), do: nil

  def text(value) do
    case value |> to_string() |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  @doc "The name of a resident, or the words for a resident with none."
  def name(%{name: name}) when is_binary(name), do: name
  def name(_resident), do: "A resident with no name"

  @doc "The name of a resident for the middle of a sentence, as in the title of its record."
  def named(%{name: name}) when is_binary(name), do: name
  def named(_resident), do: "a resident with no name"

  @doc "The labels of the values of ties, in the order of the labels, or `nil` for none."
  def labels(ties, value) do
    ties
    |> Enum.map(&to_string(Map.fetch!(&1, value).label))
    |> Enum.sort()
    |> Enum.join(", ")
    |> text()
  end

  @doc "The label of a value of a list, or `nil`."
  def label(%{label: label}), do: text(label)
  def label(_none), do: nil

  @doc "A path of locations in one line: `Main shed › Pen 3`."
  def path(names), do: Enum.join(names, " › ")

  @doc "The places of a resident in one line, or `nil` for a resident with no place."
  def homes([]), do: nil
  def homes(paths), do: paths |> Enum.map(&path/1) |> Enum.join("; ")

  @doc "The date of birth of a resident with its age on a day, or `nil`."
  def born(%{born_on: nil}, _on), do: nil

  def born(resident, on) do
    date = ResidentWords.date(resident.born_on)
    date = if resident.born_on_estimated, do: "About #{date}", else: date

    case ResidentWords.age(resident.born_on, on) do
      nil -> date
      age -> "#{date} (#{age} old)"
    end
  end

  @doc "The identifiers of a resident, each as its kind and its value."
  def identifiers(resident) do
    resident.identifiers
    |> Enum.map(&%{kind: to_string(&1.kind.label), value: &1.value})
    |> Enum.sort_by(&{&1.kind, &1.value})
  end

  @doc "A count with its noun: `1 resident`, `3 residents`."
  def count(1, one, _many), do: "1 #{one}"
  def count(number, _one, many), do: "#{amount(number)} #{many}"

  @doc "A whole number as text, in the form of the locale."
  def amount(number) when is_integer(number), do: Locale.number(number)

  @doc "The rows of a list of a label and a value, with no row for a value that is not there."
  def rows(pairs) do
    for {label, value} <- pairs, value = text(value), do: %{label: label, value: value}
  end
end
