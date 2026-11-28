defmodule Rescord.Log.Translator do
  @moduledoc """
  Keeps the messages of a process out of a crash report (ADR 0077).

  When a process stops with a fault, Elixir writes its last message. For a
  page that is the event of the person, with each field of the form, or a
  message with a record in it. `:filter_parameters` does not reach it.

  This translator stands in front of `Logger.Translator`. It replaces the
  last message of a GenServer or of an event handler, the queue of a state
  machine, and the arguments of a task with their shape
  (`Rescord.Log.shape/1`), and gives the report to the translator of Elixir.
  The exception and the stack trace stay as they are.

  At the level `debug` a report is complete, as Elixir writes it: that level
  also writes the state of the process, and it is for a person who looks
  for a fault on a machine of their own.
  """

  alias Rescord.Log.Shape

  @doc "The callback of `Logger.Translator`."
  @spec translate(Logger.level(), Logger.level(), :format | :report, term) ::
          {:ok, iodata, keyword} | {:ok, iodata} | :skip | :none
  def translate(:debug, _level, _kind, _message), do: :none

  def translate(min_level, level, :report, {:logger, %{label: label} = report})
      when label in [{:gen_server, :terminate}, {:gen_event, :terminate}] do
    report = Map.replace_lazy(report, :last_message, &Shape.of/1)
    Logger.Translator.translate(min_level, level, :report, {:logger, report})
  end

  def translate(
        min_level,
        level,
        :report,
        {:logger, %{label: {:gen_statem, :terminate}} = report}
      ) do
    report =
      report
      |> Map.replace_lazy(:queue, &shapes/1)
      |> Map.replace_lazy(:postponed, &shapes/1)

    Logger.Translator.translate(min_level, level, :report, {:logger, report})
  end

  def translate(
        min_level,
        level,
        :report,
        {{Task.Supervisor, :terminating} = label, %{} = report}
      ) do
    report = Map.replace_lazy(report, :args, &shapes/1)
    Logger.Translator.translate(min_level, level, :report, {label, report})
  end

  def translate(_min_level, _level, _kind, _message), do: :none

  defp shapes(values) when is_list(values), do: Enum.map(values, &Shape.of/1)
  defp shapes(value), do: Shape.of(value)
end
