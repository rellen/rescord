defmodule Rescord.Storage.Compare do
  @moduledoc """
  Compares the files of the store with the keys that the records of the
  database name (ADR 0091). `Rescord.Release.check_files/1` gives it both
  and prints the report, and `bin/check-files` runs that.

  Rescord writes a record first, and puts its file in the store after it,
  inside the transaction. So a fault after a put leaves a file that no
  record names: a leftover. Nothing shows such a file, and nothing deletes
  it. The other fault is a record whose file the store lost: a page that
  shows it gives an error.

  Each name of the store goes in one group:

    * `named` - a record names it;
    * `leftover` - a key of an organisation of this server that no record
      names;
    * `unknown` - a key whose first segment is no organisation of this
      server, such as the test file of a `bin/check` that stopped;
    * `other` - a name that is no key (`Rescord.Storage.key?/1`), such as
      the `lost+found` of a volume.

  And `missing` holds each key that a record names and the store does not
  list.

  This module reads no store and no database, and it changes nothing: it
  gets the list of the store and the keys of the records, and it decides
  by what the records say, and not by the shape of a key.
  """

  alias Rescord.Storage
  alias Rescord.Storage.Named

  @typedoc "A file of the store: its name and its size in bytes."
  @type file :: {String.t(), non_neg_integer}

  @typedoc "The files of a group: how many, and their size together."
  @type sum :: %{count: non_neg_integer, bytes: non_neg_integer}

  @typedoc """
  A key that the store does not have: the key, the id of the organisation
  whose record names it, each record that names it, as its kind in words
  and its id, and what the store said: `:not_found`, or why it gave no
  answer.
  """
  @type missing ::
          {Storage.key(), organisation_id :: String.t(), [{String.t(), String.t()}],
           reason :: term}

  @typedoc """
  The report: the files of the store and their size, the number of the
  organisations, and the groups of the moduledoc. Each list is in the
  order of the keys.
  """
  @type t :: %__MODULE__{
          store: sum,
          organisations: non_neg_integer,
          named: sum,
          leftover: [file],
          unknown: [file],
          other: [file],
          missing: [missing]
        }

  defstruct store: %{count: 0, bytes: 0},
            organisations: 0,
            named: %{count: 0, bytes: 0},
            leftover: [],
            unknown: [],
            other: [],
            missing: []

  @shown 20

  @doc """
  Compares `files`, the list of the store (`c:Rescord.Storage.files/0`),
  with `named`: for the id of each organisation of the server, the keys
  that its records name (`Rescord.Storage.Named`). An organisation with
  no file is in `named` too, with no key.
  """
  @spec run([file], %{String.t() => [Named.entry()]}) :: t
  def run(files, named) when is_list(files) and is_map(named) do
    records = records(named)

    report =
      Enum.reduce(files, %__MODULE__{organisations: map_size(named)}, fn {name, size}, report ->
        report = %{report | store: add(report.store, size)}

        case group(name, records, named) do
          :named -> %{report | named: add(report.named, size)}
          group -> Map.update!(report, group, &[{name, size} | &1])
        end
      end)

    listed = MapSet.new(files, &elem(&1, 0))

    missing =
      for {key, {organisation_id, records}} <- records,
          not MapSet.member?(listed, key),
          do: {key, organisation_id, records |> Enum.uniq() |> Enum.sort(), :not_found}

    %{
      report
      | leftover: Enum.sort(report.leftover),
        unknown: Enum.sort(report.unknown),
        other: Enum.sort(report.other),
        missing: Enum.sort(missing)
    }
  end

  @doc """
  Asks the store for each file of `missing`, with `get`
  (`c:Rescord.Storage.get/1`), and returns the report with what the store
  said.

  The list of the store is older than the read of the records. A file of
  an upload that ended in between is named by a record and not in the
  list, and the store has it: it then counts as named, and it is not
  missing. A file that the store did not give for another reason than
  that it is not there stays in `missing`, with that reason.
  """
  @spec confirm(t, (Storage.key() -> {:ok, binary} | {:error, term})) :: t
  def confirm(%__MODULE__{} = report, get) when is_function(get, 1) do
    report.missing
    |> Task.async_stream(fn {key, _organisation_id, _records, _reason} -> get.(key) end,
      max_concurrency: 4,
      timeout: :infinity
    )
    |> Enum.zip(report.missing)
    |> Enum.reduce(%{report | missing: []}, fn
      {{:ok, {:ok, bytes}}, _missing}, report ->
        size = byte_size(bytes)
        %{report | store: add(report.store, size), named: add(report.named, size)}

      {{:ok, {:error, reason}}, {key, organisation_id, records, _reason}}, report ->
        %{report | missing: [{key, organisation_id, records, reason} | report.missing]}
    end)
    |> then(&%{&1 | missing: Enum.reverse(&1.missing)})
  end

  @doc "Whether the store has each file that a record names."
  @spec complete?(t) :: boolean
  def complete?(%__MODULE__{} = report), do: report.missing == []

  @doc """
  The report as lines of text, for the store `store`. It prints ids, keys
  and sizes: no name of a file, no caption, and nothing that a person
  typed. It names the first #{@shown} files of a group, and each one with
  `all: true`.
  """
  @spec format(t, module, keyword) :: String.t()
  def format(%__MODULE__{} = report, store, opts \\ []) do
    shown = if Keyword.get(opts, :all, false), do: :infinity, else: @shown

    first =
      "#{capitalize(Storage.describe(store))} has #{files(report.store.count)} " <>
        "(#{Storage.size_words(report.store.bytes)}), and Rescord has " <>
        "#{organisations(report.organisations)}."

    lines =
      [
        "named     #{files(report.named.count)} (#{Storage.size_words(report.named.bytes)}) " <>
          "that a record names"
      ] ++
        group_lines("leftover  ", report.leftover, "that no record names", shown) ++
        group_lines("unknown   ", report.unknown, "of no organisation of this server", shown) ++
        other_lines(report.other) ++
        missing_lines(report.missing, shown)

    first <> "\n\n" <> Enum.join(lines, "\n") <> "\n\n" <> last(report)
  end

  @doc "The words for a comparison that could not be made, and why."
  @spec format_fault({:list | :database | :migrations, term}, module) :: String.t()
  def format_fault({:list, reason}, store) do
    "Rescord cannot list the files of #{Storage.describe(store)}: " <>
      "#{Storage.reason_words(reason)}.\nNothing was compared."
  end

  def format_fault({:database, words}, _store),
    do: "Rescord cannot read the database: #{words}.\nNothing was compared."

  def format_fault({:migrations, words}, _store) do
    "The tables are not those of this version of Rescord: of the migrations, #{words}.\n" <>
      "Start Rescord, or run bin/migrate, and run the command again. Nothing was compared."
  end

  # Each key that a record names, with the organisation and the records.
  defp records(named) do
    for {organisation_id, entries} <- named, {key, kind, id} <- entries, reduce: %{} do
      records ->
        Map.update(records, key, {organisation_id, [{kind, id}]}, fn {organisation_id, found} ->
          {organisation_id, [{kind, id} | found]}
        end)
    end
  end

  defp group(name, records, named) do
    cond do
      is_map_key(records, name) -> :named
      not Storage.key?(name) -> :other
      is_map_key(named, name |> String.split("/", parts: 2) |> hd()) -> :leftover
      true -> :unknown
    end
  end

  defp add(sum, size), do: %{count: sum.count + 1, bytes: sum.bytes + size}

  defp group_lines(_label, [], _words, _shown), do: []

  defp group_lines(label, files, words, shown) do
    bytes = files |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    ["#{label}#{files(length(files))} (#{Storage.size_words(bytes)}) #{words}"] ++
      some(files, shown, fn {key, size} -> "  #{key}  #{Storage.size_words(size)}" end)
  end

  defp other_lines([]), do: []

  defp other_lines(other) do
    names = Enum.map(other, &elem(&1, 0))
    more = if length(names) > 5, do: ", and #{length(names) - 5} more", else: ""

    [
      "other     #{length(names)} that Rescord did not put there: " <>
        Enum.join(Enum.take(names, 5), ", ") <> more
    ]
  end

  defp missing_lines([], _shown), do: []

  defp missing_lines(missing, shown) do
    ["FAIL      #{files(length(missing))} that a record names, and that the store does not have"] ++
      some(missing, shown, fn {key, organisation_id, records, reason} ->
        named = Enum.map_join(records, " and ", fn {kind, id} -> "#{kind} #{id}" end)

        why =
          if reason == :not_found,
            do: "",
            else: ". The store did not say whether it is there: #{Storage.reason_words(reason)}"

        "  #{key}: #{named}, of the organisation #{organisation_id}#{why}"
      end)
  end

  defp some(items, :infinity, line), do: Enum.map(items, line)

  defp some(items, shown, line) do
    more =
      if length(items) > shown,
        do: ["  and #{length(items) - shown} more: bin/check-files --all prints each one"],
        else: []

    (items |> Enum.take(shown) |> Enum.map(line)) ++ more
  end

  defp last(report) do
    leftover =
      if report.leftover == [] do
        []
      else
        [
          "A leftover is a file that an upload or a transfer put in the store before it failed.",
          "A file of an upload that runs now can be in this list too. Run the command",
          "again: a leftover is in both runs."
        ]
      end

    result =
      if complete?(report) do
        ["The store has each file that a record names."]
      else
        [
          "The store does not have each file that a record names: look for each FAIL in",
          "a backup of the store. A page that shows such a file gives an error."
        ]
      end

    Enum.join(leftover ++ result ++ ["Nothing was changed."], "\n")
  end

  defp files(1), do: "1 file"
  defp files(count), do: "#{count} files"

  defp organisations(1), do: "1 organisation"
  defp organisations(count), do: "#{count} organisations"

  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
end
