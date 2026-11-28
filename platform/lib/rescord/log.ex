defmodule Rescord.Log do
  @moduledoc """
  What Rescord writes in its log, and what it keeps out (ADR 0077).

  A line of the log says what happened in words. Its fields say whose it is:
  `context/1` sets them for the process, and the formatter writes them.

  A line holds no name and no address of a person, no text that a person
  typed, no token, no file, and never the message of an error: the message
  of an Ash error holds the value that Ash refused. `reason/1` gives the
  safe text of a failure and of any other value, with `Shoddy.Terms.shape/2`.

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

  # The fields of an exception that say what failed. `Shoddy.Terms.shape/2`
  # keeps one only when its value is an atom, which code wrote, or a failure
  # inside it.
  @facts [:errors, :field, :resource, :action, :code, :type, :postgres, :reason, :error]

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
  other value it gives the shape of `Shoddy.Terms.shape/2`: an atom as it
  is, the module of a struct, and the kind of each other value.

      iex> Rescord.Log.reason({:record, %{name: "Fern"}, "a note"})
      "{:record, map(1), binary}"
  """
  @spec reason(term) :: String.t()
  # A class of Splode holds the errors of an action.
  def reason(%{__exception__: true, errors: [_ | _] = errors} = error) do
    shown = errors |> Enum.take(@most) |> Enum.map_join(", ", &shape/1)
    rest = length(errors) - @most
    more = if rest > 0, do: ", and #{rest} more", else: ""

    "#{class(error)}: #{shown}#{more}"
  end

  def reason(failure), do: shape(failure)

  defp class(%{class: class}) when is_atom(class) and not is_nil(class), do: class
  defp class(%module{}), do: inspect(module)

  defp shape(failure), do: failure |> postgres_code() |> Shoddy.Terms.shape(fields: @facts)

  # The error of PostgreSQL names its kind, such as `:unique_violation`, in a
  # map with the detail, and the detail holds the value. `Shoddy.Terms.shape/2`
  # shows no map, so the kind takes the place of the map.
  defp postgres_code(%{__exception__: true, postgres: %{code: code}} = error)
       when is_atom(code) and not is_nil(code),
       do: %{error | postgres: code}

  defp postgres_code(failure), do: failure

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
