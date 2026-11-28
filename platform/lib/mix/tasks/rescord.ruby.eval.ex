defmodule Mix.Tasks.Rescord.Ruby.Eval do
  @shortdoc "Asks a real model the questions of the evaluation set of Ruby"

  @moduledoc """
  Asks a model each question of the evaluation set of Ruby, scores each
  answer by code, and prints a table (`Rescord.Ruby.Eval`).

  **It asks a real provider, and costs money.** Only a person starts it:
  it is in no test and in no workflow of a push. Twenty cases with three
  runs of each are sixty replies.

  It plants a rescue with made-up records in the database of this
  environment (`Rescord.Ruby.Eval.Seed`), and sends the provider those
  records alone. The rescue stays in the database after the run, so run
  the task against a database of development.

  The task reads no setting from the environment. It gets its provider in
  one of two ways:

      # A provider of this server: a row that a root user added on the
      # page /root/ruby. Its key stays encrypted in the database.
      mix rescord.ruby.eval --provider "Anthropic"
      mix rescord.ruby.eval --provider "Anthropic" --model claude-haiku-5-5
      mix rescord.ruby.eval --provider "Anthropic" --only care,injection

      # No row: the fields of a provider as flags, and the key on the
      # standard input. Nothing is saved.
      pass show anthropic | mix rescord.ruby.eval --kind anthropic --key-stdin --yes
      mix rescord.ruby.eval --kind ollama --model qwen3.6:27b --base-url http://10.0.0.5:11434/v1

  ## The flags

    * `--provider NAME` - a provider of this server, by its name;
    * `--model MODEL` - the model. With `--provider`, it replaces the
      model of the row for this run, and the row does not change;
    * `--kind KIND`, `--base-url URL`, `--region REGION` - the fields of a
      provider, checked by the rules of a row;
    * `--key-stdin` - reads the key as one line of the standard input.
      **The key is never a flag**: a flag is in the history of the shell
      and in the list of the processes. It needs `--yes`, because the
      standard input holds the key and cannot answer a question;
    * `--runs N` - how often each case runs, 3 by default;
    * `--only GROUPS` - the groups to run, with commas between them;
    * `--out DIRECTORY` - where the file of the run goes, `tmp/ruby-eval`
      by default, which Git ignores;
    * `--yes` - does not ask before the first request.

  The task prints where the records go and asks before the first request.
  It ends with the status 1 when a group is below its bar.
  """

  use Mix.Task

  use Boundary, top_level?: true, deps: [Rescord.Ruby, Rescord.Ruby.Eval.Seed]

  alias Rescord.Ruby.Eval
  alias Rescord.Ruby.Eval.Seed

  @requirements ["app.start"]

  @switches [
    provider: :string,
    model: :string,
    kind: :string,
    base_url: :string,
    region: :string,
    key_stdin: :boolean,
    runs: :integer,
    only: :string,
    out: :string,
    yes: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    flags = flags(args)
    groups = groups(flags[:only])
    runs = flags[:runs] || 3
    if runs not in 1..10, do: Mix.raise("--runs takes a number from 1 to 10.")

    profile = profile(flags)

    Mix.shell().info("The questions and the seeded records go to: #{Eval.place(profile)}")
    Mix.shell().info("The model is #{Eval.model(profile)}. The seed holds no real record.")

    unless flags[:yes] || Mix.shell().yes?("Send the seeded records there?"),
      do: Mix.raise("Nothing was sent.")

    seed = Seed.plant!()
    Mix.shell().info("The seeded rescue is #{seed.organisation.short_name}.")

    results =
      case seed |> Eval.cases(groups) |> Eval.run(seed, profile, runs: runs, note: &note/1) do
        {:ok, results} ->
          results

        {:error, reason} ->
          Mix.raise(
            "The provider did not answer (#{reason}). No more questions were asked. " <>
              "Check the key, the model and the address of the provider."
          )
      end

    report = Eval.report(results, profile)
    Mix.shell().info("\n" <> report.table)
    Mix.shell().info("\nThe file of the run: #{write(report, profile, flags[:out])}")

    unless report.met?, do: exit({:shutdown, 1})
  end

  defp flags(args) do
    case OptionParser.parse(args, strict: @switches) do
      {flags, [], []} ->
        Map.new(flags)

      {_flags, _rest, [{flag, _value} | _more]} when flag in ["--key", "--api-key"] ->
        Mix.raise("The key is never a flag. Give --key-stdin, and the key on the standard input.")

      {_flags, rest, wrong} ->
        Mix.raise(
          "Not understood: #{Enum.join(Enum.map(wrong, &elem(&1, 0)) ++ rest, " ")}. " <>
            "See mix help rescord.ruby.eval."
        )
    end
  end

  defp groups(nil), do: nil

  defp groups(only) do
    known = Map.new(Eval.groups(), &{Atom.to_string(&1), &1})
    names = String.split(only, ",", trim: true)

    case Enum.reject(names, &is_map_key(known, &1)) do
      [] ->
        Enum.map(names, &Map.fetch!(known, &1))

      wrong ->
        Mix.raise(
          "No group #{Enum.join(wrong, ", ")}. The groups: #{Enum.join(Map.keys(known), ", ")}."
        )
    end
  end

  defp profile(%{provider: _name} = flags) do
    if Enum.any?([:kind, :base_url, :region, :key_stdin], &is_map_key(flags, &1)),
      do: Mix.raise("Give --provider, or --kind with its flags, and not both.")

    profile!(flags)
  end

  defp profile(%{kind: _kind} = flags) do
    if flags[:key_stdin] && !flags[:yes],
      do:
        Mix.raise(
          "With --key-stdin, give --yes too: the standard input holds the key, " <>
            "so the task cannot ask its question there."
        )

    profile!(if flags[:key_stdin], do: Map.put(flags, :api_key, key()), else: flags)
  end

  defp profile(_flags),
    do: Mix.raise("Name a provider of this server (--provider), or a kind (--kind).")

  defp profile!(flags) do
    case Eval.profile(flags) do
      {:ok, profile} ->
        profile

      {:error, problems} ->
        Mix.raise(
          "The provider is not complete:\n" <>
            Enum.map_join(problems, "\n", fn {field, words} -> "  #{field}: #{words}" end)
        )
    end
  end

  # One line of the standard input. It is not printed, and it is in no
  # error.
  defp key do
    case IO.read(:stdio, :line) do
      line when is_binary(line) and line != "" ->
        case String.trim(line) do
          "" -> Mix.raise("The standard input has no key.")
          key -> key
        end

      _nothing ->
        Mix.raise("The standard input has no key.")
    end
  end

  defp note(result) do
    marks =
      Enum.map_join(result.runs, " ", fn
        %{failed: []} -> "pass"
        %{failed: failed} -> "fail (#{Enum.join(failed, ", ")})"
      end)

    Mix.shell().info("#{result.case.id}: #{marks}")
  end

  # The table and each failed answer. An answer holds text of the seed,
  # and nothing of a real rescue.
  defp write(report, profile, out) do
    directory = out || Path.join("tmp", "ruby-eval")
    File.mkdir_p!(directory)

    name =
      Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S") <>
        "-" <> String.replace(Eval.model(profile), ~r/[^A-Za-z0-9.-]+/, "-") <> ".txt"

    path = Path.join(directory, name)
    File.write!(path, report.table <> "\n\n" <> report.failures)
    path
  end
end
