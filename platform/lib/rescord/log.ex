defmodule Rescord.Log do
  @moduledoc """
  What Rescord writes in its log, and what it keeps out (ADR 0077).

  A line of the log says what happened in words. Its fields say whose it is:
  `context/1` sets them for the process, and the formatter writes them.

  A line holds no name and no address of a person, no text that a person
  typed, no token, no file, and never the message of an error: the message
  of an Ash error holds the value that Ash refused. `reason/1` gives the
  safe text of a failure, and `shape/1` gives the safe text of any value.

      Logger.warning("The email of an invitation failed: \#{Rescord.Log.reason(error)}")

  The arguments of a call of `Logger` use no `inspect` and no function of
  `Exception`. `Rescord.LogRulesTest` reads the code and holds that.

  `attach/0` puts two things in place when the application starts:
  `Rescord.Log.Translator`, which keeps the messages of a process out of a
  crash report, and `Rescord.Log.Jobs`, which writes a line for a job that
  fails.
  """

  alias Rescord.Log.{Jobs, Translator}

  @context [:user, :organisation, :job, :worker, :queue, :attempt]

  # The fields of an exception that say what failed. The text keeps one only
  # when its value is an atom, which code wrote, or a failure inside it.
  @facts [:field, :fields, :resource, :action, :code, :type, :postgres, :reason, :error]

  @depth 4
  @most 5
  @frames 12

  @doc """
  The fields of a line of the log, in the order of the formatter.
  `config/config.exs` names the same list.
  """
  @spec fields() :: [atom]
  def fields, do: [:request_id | @context]

  @doc """
  Sets fields of the log for this process: the id of the user, the id of the
  organisation, and what a job is. It keeps a field only when its value is
  an id, a number or an atom.

      Rescord.Log.context(user: user.id, organisation: organisation.id)
  """
  @spec context(keyword) :: :ok
  def context(fields) when is_list(fields) do
    fields
    |> Enum.filter(fn {key, value} -> key in @context and plain?(value) end)
    |> Logger.metadata()
  end

  defp plain?(value) when is_binary(value) or is_integer(value), do: true
  defp plain?(value), do: is_atom(value) and not is_nil(value)

  @doc "Adds the translator of the crash reports and the lines of the jobs."
  @spec attach() :: :ok
  def attach do
    Logger.add_translator({Translator, :translate})
    Jobs.attach()
  end

  @doc """
  The safe text of a failure, for a line of the log.

  For an error of Ash, or any Splode error, it gives the class and the
  module of each error, with the fields that are atoms:

      "invalid: Ash.Error.Changes.Required(field: :name)"

  For any other exception it gives the module, and the reason when that is
  an atom: `"DBConnection.ConnectionError(reason: :queue_timeout)"`. For each
  other value it gives the shape, as `shape/1` does.
  """
  @spec reason(term) :: String.t()
  def reason(failure), do: shape(failure)

  @doc """
  The shape of a value, with nothing that a person wrote: an atom as it is,
  the module of a struct, and the kind of each other value.

      iex> Rescord.Log.shape({:record, %{name: "Fern"}, "a note"})
      "{:record, map(1), binary}"
  """
  @spec shape(term) :: String.t()
  def shape(value), do: shape(value, 0)

  defp shape(value, _depth) when is_atom(value), do: inspect(value)
  defp shape(value, _depth) when is_binary(value), do: "binary"
  defp shape(value, _depth) when is_bitstring(value), do: "bitstring"
  defp shape(value, _depth) when is_integer(value), do: "integer"
  defp shape(value, _depth) when is_float(value), do: "float"
  defp shape(value, _depth) when is_pid(value), do: "pid"
  defp shape(value, _depth) when is_reference(value), do: "reference"
  defp shape(value, _depth) when is_port(value), do: "port"
  defp shape(value, _depth) when is_function(value), do: "function"
  defp shape([], _depth), do: "[]"
  defp shape(value, _depth) when is_list(value), do: "list"
  defp shape(%{__exception__: true} = error, depth), do: exception(error, depth)
  defp shape(%module{}, _depth), do: "%#{inspect(module)}{}"
  defp shape(value, _depth) when is_map(value), do: "map(#{map_size(value)})"

  defp shape(value, depth) when is_tuple(value) and depth < @depth and tuple_size(value) <= 6 do
    "{" <> (value |> Tuple.to_list() |> Enum.map_join(", ", &shape(&1, depth + 1))) <> "}"
  end

  defp shape(value, _depth) when is_tuple(value), do: "tuple(#{tuple_size(value)})"

  # A class of Splode holds the errors of an action.
  defp exception(%module{errors: [_ | _] = errors} = error, depth) when depth < @depth do
    shown = errors |> Enum.take(@most) |> Enum.map_join(", ", &shape(&1, depth + 1))
    rest = length(errors) - @most
    more = if rest > 0, do: ", and #{rest} more", else: ""

    case Map.get(error, :class) do
      class when is_atom(class) and not is_nil(class) -> "#{class}: #{shown}#{more}"
      _no_class -> "#{inspect(module)}: #{shown}#{more}"
    end
  end

  defp exception(%module{} = error, depth) do
    fields = Map.from_struct(error)

    case for key <- @facts, text = fact(key, Map.get(fields, key), depth), do: "#{key}: #{text}" do
      [] -> inspect(module)
      facts -> "#{inspect(module)}(#{Enum.join(facts, ", ")})"
    end
  end

  defp fact(_key, value, _depth) when is_nil(value) or is_boolean(value), do: nil
  defp fact(_key, value, _depth) when is_atom(value), do: inspect(value)

  defp fact(:fields, [_ | _] = names, _depth) do
    if Enum.all?(names, &is_atom/1), do: inspect(Enum.take(names, @most))
  end

  # The error of PostgreSQL names its kind, such as `:unique_violation`.
  defp fact(:postgres, %{code: code}, _depth) when is_atom(code) and not is_nil(code),
    do: inspect(code)

  # An exception that wraps another failure, as that of a job does.
  defp fact(key, value, depth) when key in [:reason, :error] and depth < @depth,
    do: shape(value, depth + 1)

  defp fact(_key, _value, _depth), do: nil

  @doc """
  A stack trace as text, with no argument of a call: a frame can hold the
  values that a function got.
  """
  @spec stacktrace(Exception.stacktrace()) :: String.t()
  def stacktrace([]), do: ""

  def stacktrace(frames) when is_list(frames) do
    frames
    |> Enum.take(@frames)
    |> Enum.map(fn
      {module, function, arguments, location} when is_list(arguments) ->
        {module, function, length(arguments), location}

      frame ->
        frame
    end)
    |> Exception.format_stacktrace()
  end
end
