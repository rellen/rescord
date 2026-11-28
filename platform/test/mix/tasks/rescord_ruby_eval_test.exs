defmodule Mix.Tasks.Rescord.Ruby.EvalTest do
  @moduledoc """
  Holds the task `mix rescord.ruby.eval` (ADR 0069) with no model: its
  flags, where the key comes from, the question before the first request,
  the table and the file of a run.

  The model answers from a script. No test calls a provider.

  The task creates an organisation, so the test does not run beside
  others.
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureIO
  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Mix.Tasks.Rescord.Ruby.Eval, as: Task
  alias Rescord.Ruby.ScriptedModel

  @moduletag :tmp_dir

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

  # Each line that the task printed.
  defp printed(lines \\ []) do
    receive do
      {:mix_shell, :info, [line]} -> printed([line | lines])
      {:mix_shell, :yes?, [line]} -> printed([line | lines])
    after
      0 -> lines |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp seeded,
    do:
      Enum.filter(
        Rescord.Accounts.organisations!(authorize?: false),
        &(&1.short_name =~ "ruby-eval-")
      )

  # The three cases of the group `none`, each with a right answer.
  defp none_script do
    [
      {:tool, "find_residents", %{}},
      {:text, "The records hold no resident named Mango."},
      {:tool, "tasks_for_day", %{}},
      {:text, "Nothing is planned for that day."},
      {:text, "I cannot read the stock: the records that I read hold nothing about it."}
    ]
  end

  describe "the flags" do
    test "never take the key" do
      for flag <- ["--key", "--api-key"] do
        assert_raise Mix.Error, ~r/The key is never a flag/, fn ->
          Task.run(["--kind", "anthropic", flag, key()])
        end
      end
    end

    test "name a provider or a kind, and not both" do
      assert_raise Mix.Error, ~r/Name a provider of this server/, fn -> Task.run([]) end

      assert_raise Mix.Error, ~r/and not both/, fn ->
        Task.run(["--provider", "Anthropic", "--kind", "anthropic"])
      end

      assert_raise Mix.Error, ~r/Not understood: --nothing/, fn ->
        Task.run(["--provider", "Anthropic", "--nothing"])
      end

      assert_raise Mix.Error, ~r/No group nothing/, fn ->
        Task.run(["--provider", "Anthropic", "--only", "care,nothing"])
      end

      assert_raise Mix.Error, ~r/--runs takes a number from 1 to 10/, fn ->
        Task.run(["--provider", "Anthropic", "--runs", "0"])
      end

      assert seeded() == []
    end

    test "say what is wrong with a provider, by field" do
      assert_raise Mix.Error, ~r/no provider with the name Anthropic/, fn ->
        Task.run(["--provider", "Anthropic"])
      end

      assert_raise Mix.Error, ~r/api_key: /, fn -> Task.run(["--kind", "anthropic"]) end

      # The standard input holds the key, so it cannot answer a question.
      assert_raise Mix.Error, ~r/With --key-stdin, give --yes too/, fn ->
        Task.run(["--kind", "anthropic", "--key-stdin"])
      end

      capture_io([input: "\n"], fn ->
        assert_raise Mix.Error, ~r/The standard input has no key/, fn ->
          Task.run(["--kind", "anthropic", "--key-stdin", "--yes"])
        end
      end)

      assert seeded() == []
    end
  end

  describe "a run" do
    test "with the fields of a provider and the key on the standard input", context do
      ScriptedModel.script(none_script())

      capture_io([input: key() <> "\n"], fn ->
        Task.run(
          ~w(--kind anthropic --model claude-haiku-5-5 --key-stdin --yes) ++
            ~w(--only none --runs 1 --out #{context.tmp_dir})
        )
      end)

      printed = printed()

      assert printed =~ "The questions and the seeded records go to: "
      assert printed =~ "The model is claude-haiku-5-5. The seed holds no real record."
      assert printed =~ ~r/The seeded rescue is ruby-eval-\d{14}-[0-9a-f]{4}\./
      assert printed =~ "none-no-such-resident: pass"
      assert printed =~ "none-no-tool: pass"
      assert printed =~ "none        3/3     3/3     100%  yes"
      # The key is in no line.
      refute printed =~ key()

      # The requests went with the key and the model of the flags.
      requests = ScriptedModel.requests()
      assert length(requests) == 5
      assert Enum.all?(requests, &(&1.opts[:api_key] == key()))
      assert Enum.all?(requests, &match?(%{id: "claude-haiku-5-5"}, &1.model))

      # The file of the run has the table, and no key.
      assert [name] = File.ls!(context.tmp_dir)
      assert name =~ ~r/\A\d{8}-\d{6}-claude-haiku-5-5\.txt\z/
      file = File.read!(Path.join(context.tmp_dir, name))
      assert file =~ "none        3/3     3/3     100%  yes"
      refute file =~ key()

      assert [_rescue] = seeded()
      # Nothing of a provider was saved.
      assert Rescord.Ruby.providers!(authorize?: false) == []
    end

    test "with a provider of the server asks before the first request", context do
      root = root!()
      provider!(root)
      ScriptedModel.script([])

      send(self(), {:mix_shell_input, :yes?, false})

      assert_raise Mix.Error, ~r/Nothing was sent/, fn ->
        Task.run(~w(--provider Anthropic --only none --runs 1 --out #{context.tmp_dir}))
      end

      assert printed() =~ "Send the seeded records there?"
      assert ScriptedModel.requests() == []
      assert seeded() == []
      assert File.ls!(context.tmp_dir) == []
    end

    test "stops when the provider refuses the key", context do
      root = root!()
      provider!(root)

      ScriptedModel.script([
        {:raise,
         ReqLLM.Error.API.Stream.exception(
           reason: "HTTP 401",
           cause: ReqLLM.Error.API.Request.exception(reason: "No such key", status: 401)
         )}
      ])

      assert_raise Mix.Error, ~r/The provider did not answer \(key_refused\)/, fn ->
        Task.run(~w(--provider Anthropic --yes --out #{context.tmp_dir}))
      end

      assert length(ScriptedModel.requests()) == 1
      assert File.ls!(context.tmp_dir) == []
    end

    test "ends with the status 1 when a group is below its bar", context do
      root = root!()
      provider!(root)

      ScriptedModel.script([
        {:tool, "find_residents", %{}},
        {:text, "Mango is doing well."} | Enum.drop(none_script(), 2)
      ])

      send(self(), {:mix_shell_input, :yes?, true})

      assert catch_exit(
               Task.run(~w(--provider Anthropic --only none --runs 1 --out #{context.tmp_dir}))
             ) == {:shutdown, 1}

      printed = printed()
      assert printed =~ "none-no-such-resident: fail (says, does_not_say)"
      assert printed =~ "none        2/3     2/3     100%  no"

      # The file has the failed answer, for a person to read.
      assert [name] = File.ls!(context.tmp_dir)
      file = File.read!(Path.join(context.tmp_dir, name))
      assert file =~ "none-no-such-resident, run 1\nfailed: says, does_not_say"
      assert file =~ "answer:\nMango is doing well."
    end
  end
end
