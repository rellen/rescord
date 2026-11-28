# This script reads the JSON report of muex and writes the summary of the
# job of `.github/workflows/mutation.yml` (ADR 0104). It also writes a warning
# annotation for each mutant that survives and for each mutant that no test
# runs. GitHub shows at most ten warnings of a step, so the table of the
# summary lists each one.
#
# The script always exits with the status 0, also for a report that it cannot
# read and for an error of its own. Thus it cannot make a check fail.
#
# The first argument is the path of the report. The optional second argument
# is the directory of the Mix project, relative to the root of the repository
# (`platform`). muex names each file from the Mix project, and an annotation
# names it from the root.
#
# It comes from the script of the same name in rellen/shoddy.

defmodule MuexSummary do
  @moduledoc false

  @rows [
    {"Killed", "killed"},
    {"Survived", "survived"},
    {"No coverage", "no_coverage"},
    {"Invalid", "invalid"},
    {"Timeout", "timeout"},
    {"Equivalent", "equivalent"},
    {"Total", "total"}
  ]

  @gaps %{"survived" => "survived", "no_coverage" => "has no test that runs it"}

  def main(args) do
    run(args)
  rescue
    error ->
      IO.puts(
        "::warning::" <> escape_data("The summary script failed: " <> Exception.message(error))
      )
  end

  defp run([path]), do: run([path, ""])

  defp run([path, root]) do
    case File.read(path) do
      {:ok, json} ->
        json |> decode() |> report(root)

      {:error, _reason} ->
        write_note(
          "muex wrote no report. It writes none when it finds nothing to mutate, such as when no file of lib changed, and none when it stops with a fault."
        )
    end
  end

  defp run(args) do
    raise ArgumentError,
          "expected the path of a report and an optional directory, got: #{inspect(args)}"
  end

  defp decode(json) do
    case JSON.decode(json) do
      {:ok, %{"summary" => summary, "mutations" => mutations}}
      when is_map(summary) and is_list(mutations) ->
        {:ok, summary, Enum.filter(mutations, &is_map/1)}

      {:ok, _other} ->
        {:error, "the report has no summary or no list of mutants"}

      {:error, reason} ->
        {:error, "the report is not valid JSON: #{inspect(reason)}"}
    end
  end

  defp report({:error, reason}, _root),
    do: write_note("This script cannot read the report of muex: #{reason}.")

  defp report({:ok, summary, mutations}, root) do
    gaps =
      mutations
      |> Enum.filter(&Map.has_key?(@gaps, &1["status"]))
      |> Enum.sort_by(&{file(&1), line(&1)})

    rows =
      Enum.map_join(@rows, "\n", fn {label, key} -> "| #{label} | #{cell(summary[key])} |" end)

    write_summary("""
    ## Mutation testing

    This run reports the result only. It does not make a check fail.
    #{partial_note(summary)}
    | Result | Count |
    |---|---|
    #{rows}

    Mutation score: #{cell(summary["mutation_score_low"])}%

    Do not trust the invalid count. muex sometimes reports a mutant as invalid,
    although the mutant compiles and the tests kill it.
    #{gaps_section(gaps, root)}
    """)

    Enum.each(gaps, &annotate(&1, root))
  end

  defp partial_note(%{"partial" => true} = summary) do
    """

    **Partial**: the time budget ended after #{cell(summary["mutations_run"])} of
    #{cell(summary["mutations_total"])} mutants. The counts are of the mutants that ran, so do
    not compare the score with the score of a complete run.
    """
  end

  defp partial_note(_summary), do: ""

  defp gaps_section([], _root),
    do: "\nNo mutant survived, and each mutant has a test that runs it.\n"

  defp gaps_section(gaps, root) do
    rows =
      Enum.map_join(gaps, "\n", fn mutant ->
        "| #{place(mutant, root)} | #{cell(@gaps[mutant["status"]])} | #{cell(mutant["description"])} |"
      end)

    """

    ### Gaps in the tests

    No test kills the mutants below.

    | Location | Result | Change |
    |---|---|---|
    #{rows}
    """
  end

  defp annotate(mutant, root) do
    message = escape_data("A mutant #{@gaps[mutant["status"]]}: #{mutant["description"]}")

    case {file(mutant), line(mutant)} do
      {file, line} when is_binary(file) and is_integer(line) ->
        IO.puts(
          "::warning file=#{escape_property(from_root(file, root))},line=#{line}::#{message}"
        )

      _other ->
        IO.puts("::warning::#{message}")
    end
  end

  defp place(mutant, root) do
    case {file(mutant), line(mutant)} do
      {file, line} when is_binary(file) -> "`#{cell(from_root(file, root))}:#{cell(line)}`"
      _other -> "unknown"
    end
  end

  defp file(%{"location" => %{"file" => file}}) when is_binary(file), do: file
  defp file(_mutant), do: nil

  defp line(%{"location" => %{"line" => line}}), do: line
  defp line(_mutant), do: nil

  # muex names a file from the Mix project. An absolute path stays as it is.
  defp from_root(file, ""), do: file

  defp from_root(file, root) do
    if Path.type(file) == :absolute, do: file, else: Path.join(root, file)
  end

  defp write_note(note) do
    write_summary("""
    ## Mutation testing

    #{note} Examine the log of the step that runs muex.
    """)

    IO.puts("::warning::" <> escape_data(note))
  end

  defp write_summary(text) do
    case System.get_env("GITHUB_STEP_SUMMARY") do
      nil -> IO.write(text)
      file -> File.write!(file, text, [:append])
    end
  end

  defp cell(value) do
    value
    |> to_string()
    |> String.replace("|", "\\|")
    |> String.replace(~r/\s*\R\s*/, " ")
  end

  defp escape_data(text) do
    text
    |> String.replace("%", "%25")
    |> String.replace("\r", "%0D")
    |> String.replace("\n", "%0A")
  end

  defp escape_property(text) do
    text
    |> escape_data()
    |> String.replace(":", "%3A")
    |> String.replace(",", "%2C")
  end
end

MuexSummary.main(System.argv())
