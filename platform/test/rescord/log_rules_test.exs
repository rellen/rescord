defmodule Rescord.LogRulesTest do
  @moduledoc """
  Reads the code of `lib/`, and fails for a call of `Logger` whose arguments
  use `inspect` or a function of `Exception` (ADR 0077). `inspect` of an
  error and the message of an Ash error hold the values of a record. A
  value goes into a line through `Rescord.Log.reason/1` or
  `Rescord.Log.shape/1`.
  """

  use ExUnit.Case, async: true

  @levels [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency, :log]

  defp logger_calls(ast) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:Logger]}, level]}, meta, arguments} = node, calls
        when level in @levels ->
          {node, [{meta[:line], arguments} | calls]}

        node, calls ->
          {node, calls}
      end)

    calls
  end

  defp unsafe?(arguments) do
    {_ast, found?} =
      Macro.prewalk(arguments, false, fn
        {:inspect, _, list} = node, _found? when is_list(list) -> {node, true}
        {{:., _, [{:__aliases__, _, [:Exception]}, _]}, _, _} = node, _found? -> {node, true}
        {{:., _, [{:__aliases__, _, [:Kernel]}, :inspect]}, _, _} = node, _found? -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  defp faults(source) do
    for {line, arguments} <- source |> Code.string_to_quoted!() |> logger_calls(),
        unsafe?(arguments),
        do: line
  end

  test "the rule finds inspect and Exception in a call of Logger" do
    source = ~S"""
    defmodule Sample do
      require Logger

      def a(error), do: Logger.error("failed: #{inspect(error)}")
      def b(error), do: Logger.warning("failed: " <> Exception.message(error))
      def c(error), do: Logger.info(fn -> Exception.format(:error, error) end)
      def d(error), do: Logger.error("failed: #{Rescord.Log.reason(error)}")
      def e(error), do: inspect(error)
    end
    """

    assert Enum.sort(faults(source)) == [4, 5, 6]
  end

  test "no call of Logger in lib/ uses inspect or Exception" do
    files = Path.wildcard("lib/**/*.ex")
    assert length(files) > 100

    found = for file <- files, line <- faults(File.read!(file)), do: "#{file}:#{line}"

    assert found == [],
           "A line of the log holds no message of an error and no inspected value. " <>
             "Use Rescord.Log.reason/1 or Rescord.Log.shape/1 in:\n" <> Enum.join(found, "\n")
  end
end
