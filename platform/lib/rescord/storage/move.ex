defmodule Rescord.Storage.Move do
  @moduledoc """
  Copies each file of one store into another (ADR 0059), for a server that
  changes its store: from a directory to a bucket of S3, or back.
  `Rescord.Release.move_storage/2` runs it and prints the report, and
  `bin/move-storage` runs that.

  For each key of the store `from`:

    * the store `to` does not list it: the file is put there, read back,
      and compared with the bytes of `from`;
    * the store `to` lists it: the two files are read and compared. The
      same bytes need no copy. Other bytes are a fault, and the file of
      `to` stays as it is.

  So a second run copies only what is missing, and a run that stopped in
  the middle is safe to start again. A run deletes nothing in either
  store, and writes over no file that `to` lists. Rescord never changes a
  file, so a run beside a server that works copies each file that was
  there when the run listed `from`.

  A name of `from` that is no key (`Rescord.Storage.key?/1`) is not a file
  of Rescord, and stays where it is: the report names it.

  A file is in memory while it is copied, one for each of the
  `:concurrency` copies at one time. A file of Rescord is 20 MB at most.
  """

  alias Rescord.{Images, Storage}

  @typedoc """
  The report of a run:

    * `files` - the keys of `from`, and `there` - the names that `to`
      listed before the run;
    * `copied` - the files put in `to` and read back, and `bytes`, their
      size together;
    * `same` - the files that `to` had already, with the same bytes;
    * `left` - the names of `from` that are no key;
    * `failed` - each file that is not in `to` as it is in `from`, with the
      step that failed and what it gave.
  """
  @type t :: %__MODULE__{
          files: non_neg_integer,
          there: non_neg_integer,
          copied: non_neg_integer,
          bytes: non_neg_integer,
          same: non_neg_integer,
          left: [String.t()],
          failed: [{Storage.key(), step, reason :: term}]
        }

  @typedoc """
  The step that failed for a file: `:read` from `from`, `:put` in `to`,
  `:check` of what `to` gives back after a put, or `:compare` with the
  file that `to` had already. The reason `:differs` says that `to` gave
  other bytes than `from`.
  """
  @type step :: :read | :put | :check | :compare

  defstruct files: 0, there: 0, copied: 0, bytes: 0, same: 0, left: [], failed: []

  @concurrency 4

  @doc """
  Copies each file of the store `from` that the store `to` does not have,
  and checks each file of `from` against `to`.

  ## Options

    * `:concurrency` - the number of files at one time, #{@concurrency} at
      first;
    * `:progress` - a function that gets the report before the first file
      and after each file.

  It returns `{:error, {:list, :from | :to, reason}}` when a store cannot
  list its files, before it copies anything.
  """
  @spec run(module, module, keyword) :: {:ok, t} | {:error, {:list, :from | :to, term}}
  def run(from, to, opts \\ []) when is_atom(from) and is_atom(to) and from != to do
    progress = Keyword.get(opts, :progress, fn _report -> :ok end)
    concurrency = Keyword.get(opts, :concurrency, @concurrency)

    with {:from, {:ok, names}} <- {:from, from.list()},
         {:to, {:ok, there}} <- {:to, to.list()} do
      {keys, left} = names |> Enum.sort() |> Enum.split_with(&Storage.key?/1)
      there = MapSet.new(there)
      report = %__MODULE__{files: length(keys), there: MapSet.size(there), left: left}
      progress.(report)

      report =
        keys
        |> Task.async_stream(&{&1, move(&1, from, to, MapSet.member?(there, &1))},
          max_concurrency: concurrency,
          ordered: false,
          timeout: :infinity
        )
        |> Enum.reduce(report, fn {:ok, {key, outcome}}, report ->
          report = add(report, key, outcome)
          progress.(report)
          report
        end)

      {:ok, %{report | failed: Enum.sort(report.failed)}}
    else
      {side, {:error, reason}} -> {:error, {:list, side, reason}}
    end
  end

  @doc "The number of files of the report that the run has finished."
  @spec done(t) :: non_neg_integer
  def done(%__MODULE__{} = report),
    do: report.copied + report.same + length(report.failed)

  @doc "Whether each file of `from` is in `to`, with the same bytes."
  @spec complete?(t) :: boolean
  def complete?(%__MODULE__{} = report), do: report.failed == []

  @doc """
  A line for an operator who waits: the files of each store before the
  first file, and then the count after each 100 files. `nil` at each
  other time.
  """
  @spec progress_line(t, module, module) :: String.t() | nil
  def progress_line(%__MODULE__{} = report, from, to) do
    done = done(report)

    cond do
      done == 0 ->
        "#{capitalize(Storage.describe(from))} has #{files(report.files)}, " <>
          "and #{Storage.describe(to)} has #{report.there}."

      rem(done, 100) == 0 and done < report.files ->
        "  #{done} of #{report.files}"

      true ->
        nil
    end
  end

  @doc """
  The report as lines of text, for a run from the store `from` into the
  store `to`. It names the first 20 files that failed, and no secret.
  """
  @spec format(t, module, module) :: String.t()
  def format(%__MODULE__{} = report, from, to) do
    from = Storage.describe(from)
    to = Storage.describe(to)

    lines =
      copied_lines(report) ++
        same_lines(report, to) ++ left_lines(report.left) ++ failed_lines(report.failed)

    last =
      if complete?(report) do
        "Each file of #{from} is in #{to}.\n" <>
          "Nothing was deleted: #{from} keeps its files."
      else
        "Not each file of #{from} is in #{to}.\n" <>
          "Fix each FAIL, and run the command again: it copies only what is missing."
      end

    Enum.join(lines, "\n") <> "\n\n" <> last
  end

  @doc "The words for a store that could not list its files."
  @spec format_fault({:list, :from | :to, term}, module, module) :: String.t()
  def format_fault({:list, side, reason}, from, to) do
    store = if side == :from, do: from, else: to

    "Rescord cannot list the files of #{Storage.describe(store)}: #{Storage.reason_words(reason)}.\n" <>
      "Nothing was copied."
  end

  defp copied_lines(%{copied: 0}), do: ["copied  0 files"]

  defp copied_lines(report),
    do: [
      "copied  #{files(report.copied)} (#{Storage.size_words(report.bytes)}), and read each one back"
    ]

  defp same_lines(%{same: 0}, _to), do: []

  defp same_lines(report, to),
    do: ["same    #{files(report.same)} that #{to} had already, with the same bytes"]

  defp left_lines([]), do: []

  defp left_lines(left) do
    [
      "left    #{length(left)} that Rescord did not put there, and does not copy: " <>
        some(left, 5)
    ]
  end

  defp failed_lines([]), do: []

  defp failed_lines(failed) do
    shown =
      failed
      |> Enum.take(20)
      |> Enum.map(fn {key, step, reason} -> "  #{key}: #{failure_words(step, reason)}" end)

    more = if length(failed) > 20, do: ["  and #{length(failed) - 20} more"], else: []

    ["FAIL    #{files(length(failed))}"] ++ shown ++ more
  end

  defp failure_words(:read, reason),
    do: "the store did not give it: #{Storage.reason_words(reason)}"

  defp failure_words(:put, reason),
    do: "the new store did not take it: #{Storage.reason_words(reason)}"

  defp failure_words(:check, :differs),
    do: "the new store gives back other bytes than it took"

  defp failure_words(:check, reason),
    do: "the new store did not give it back: #{Storage.reason_words(reason)}"

  defp failure_words(:compare, :differs),
    do: "the new store has other bytes under this key, which stay as they are"

  defp failure_words(:compare, reason),
    do: "the new store did not give it: #{Storage.reason_words(reason)}"

  defp files(1), do: "1 file"
  defp files(count), do: "#{count} files"

  defp some(names, count) do
    shown = names |> Enum.take(count) |> Enum.join(", ")
    if length(names) > count, do: shown <> ", and #{length(names) - count} more", else: shown
  end

  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  defp add(report, _key, {:copied, size}),
    do: %{report | copied: report.copied + 1, bytes: report.bytes + size}

  defp add(report, _key, :same), do: %{report | same: report.same + 1}

  defp add(report, key, {:failed, step, reason}),
    do: %{report | failed: [{key, step, reason} | report.failed]}

  # One file. A fault of one file is in the report, and the run goes on.
  defp move(key, from, to, there?) do
    case from.get(key) do
      {:ok, bytes} when there? -> compare(key, bytes, to)
      {:ok, bytes} -> copy(key, bytes, to)
      {:error, reason} -> {:failed, :read, reason}
    end
  end

  defp compare(key, bytes, to) do
    case to.get(key) do
      {:ok, ^bytes} -> :same
      {:ok, _other} -> {:failed, :compare, :differs}
      # The list of `to` named it, and it is not there: copy it.
      {:error, :not_found} -> copy(key, bytes, to)
      {:error, reason} -> {:failed, :compare, reason}
    end
  end

  defp copy(key, bytes, to) do
    with {:put, :ok} <- {:put, to.put(key, bytes, type_of(bytes))},
         {:check, {:ok, ^bytes}} <- {:check, to.get(key)} do
      {:copied, byte_size(bytes)}
    else
      {:check, {:ok, _other}} -> {:failed, :check, :differs}
      {step, {:error, reason}} -> {:failed, step, reason}
    end
  end

  # The type that a bucket keeps beside a file. Rescord does not read it
  # back: the record of the file holds the type, and a page names the type
  # of the first bytes. A directory keeps no type, so the first bytes give
  # it here too.
  defp type_of(<<"%PDF-", _rest::binary>>), do: "application/pdf"
  defp type_of(bytes), do: Images.type_of(bytes) || "application/octet-stream"
end
