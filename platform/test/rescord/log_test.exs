defmodule Rescord.LogTest do
  @moduledoc """
  Holds what `Rescord.Log` writes about a failure and about a value, and
  what a crash report of a process holds (ADR 0077).
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Rescord.Log
  alias Rescord.Log.Translator

  doctest Rescord.Log

  defmodule Stops do
    @moduledoc false
    use GenServer

    @impl true
    def init(state), do: {:ok, state}

    @impl true
    def handle_cast({:note, _text}, _state), do: raise("no room")
  end

  defmodule NotThere do
    @moduledoc false
    use Splode.Error, fields: [:what, :typed], class: :invalid

    def message(%{what: what}), do: "the #{what} is not there"
  end

  describe "reason/1" do
    test "names the class and the errors of an Ash error, and not the value" do
      error =
        Ash.Error.to_error_class([
          Ash.Error.Changes.InvalidAttribute.exception(
            field: :email,
            message: "is not an address",
            value: "fern@example.org"
          ),
          Ash.Error.Changes.Required.exception(field: :name, type: :attribute)
        ])

      # The message of the same error holds the value, which is why no line
      # of the log holds a message.
      assert Exception.message(error) =~ "fern@example.org"

      reason = Log.reason(error)

      assert reason ==
               "invalid: Ash.Error.Changes.InvalidAttribute(field: :email), " <>
                 "Ash.Error.Changes.Required(field: :name, type: :attribute)"

      refute reason =~ "fern"
      refute reason =~ "address"
    end

    test "names a Splode error of our own, with the fields that are atoms" do
      error =
        Ash.Error.to_error_class(NotThere.exception(what: :prescription, typed: "a note of Fern"))

      assert Log.reason(error) == "invalid: Rescord.LogTest.NotThere"
      refute Log.reason(error) =~ "Fern"
    end

    test "says how many errors it leaves out" do
      errors = for n <- 1..7, do: Ash.Error.Changes.Required.exception(field: :"f#{n}")
      assert Log.reason(Ash.Error.to_error_class(errors)) =~ ", and 2 more"
    end

    test "names the module of another exception, and a reason that is an atom" do
      assert Log.reason(%RuntimeError{message: "the note of Fern"}) == "RuntimeError"

      assert Log.reason(%DBConnection.ConnectionError{message: "late", reason: :queue_timeout}) ==
               "DBConnection.ConnectionError(reason: :queue_timeout)"

      assert Log.reason(%Postgrex.Error{
               postgres: %{code: :unique_violation, detail: "Key (email)=(fern@example.org)"}
             }) == "Postgrex.Error(postgres: :unique_violation)"
    end

    test "reads the failure that the error of a job wraps" do
      error = Oban.PerformError.exception({Rescord.SomeWorker, {:error, "fern@example.org"}})

      assert Exception.message(error) =~ "fern@example.org"
      assert Log.reason(error) == "Oban.PerformError(reason: {:error, binary})"
    end

    test "names the errors of an Ash error inside another failure" do
      invalid = Ash.Error.to_error_class(Ash.Error.Changes.Required.exception(field: :name))

      assert Log.reason({:error, invalid}) ==
               "{:error, Ash.Error.Invalid(errors: [Ash.Error.Changes.Required(field: :name)])}"
    end

    test "gives an atom as it is, and the shape of each other value" do
      assert Log.reason(:timeout) == ":timeout"
      assert Log.reason({:error, :econnrefused}) == "{:error, :econnrefused}"
      assert Log.reason("the mail server said no to fern@example.org") == "binary"

      assert Log.reason({:retries_exceeded, {:network_failure, ~c"mail", {:error, :timeout}}}) ==
               "{:retries_exceeded, {:network_failure, list, {:error, :timeout}}}"
    end
  end

  describe "reason/1 for a value that is not a failure" do
    test "holds nothing of a value but its kind" do
      assert Log.reason(%{name: "Fern", sex: :female}) == "map(2)"
      assert Log.reason([1, 2, 3]) == "list"
      assert Log.reason([]) == "[]"
      assert Log.reason(42) == "integer"
      assert Log.reason(4.2) == "float"
      assert Log.reason(self()) == "pid"
      assert Log.reason(make_ref()) == "reference"
      assert Log.reason(fn -> :ok end) == "function"
      assert Log.reason(<<1::3>>) == "bitstring"
      assert Log.reason(%URI{path: "/fern"}) == "%URI{}"
      assert Log.reason({:a, "b", {:c, %{}}}) == "{:a, binary, {:c, map(0)}}"
    end

    test "stops at a tuple that is deep" do
      assert Log.reason({1, {2, {3, {4, {5, {6}}}}}}) ==
               "{integer, {integer, {integer, {integer, tuple(2)}}}}"
    end
  end

  describe "stacktrace/1" do
    test "writes the number of the arguments of a call, and not the arguments" do
      text = Log.stacktrace([{String, :upcase, ["the note of Fern"], [file: ~c"x.ex", line: 3]}])

      assert text =~ "String.upcase/1"
      refute text =~ "Fern"
      assert Log.stacktrace([]) == ""
    end
  end

  describe "context/1" do
    setup do
      before = Logger.metadata()
      Logger.reset_metadata()
      on_exit(fn -> Logger.reset_metadata(before) end)
    end

    test "sets the fields of the log, and only an id, a number or an atom" do
      Log.context(user: "0a1b", organisation: "2c3d", attempt: 2, worker: Rescord.SomeWorker)
      Log.context(user: %{email: "fern@example.org"}, job: nil, other: "x", queue: {:a, :b})

      assert Enum.sort(Logger.metadata()) ==
               [attempt: 2, organisation: "2c3d", user: "0a1b", worker: Rescord.SomeWorker]
    end

    test "the formatter writes the same fields" do
      formatter = Application.fetch_env!(:logger, :default_formatter)
      assert formatter[:metadata] == Log.fields()
    end
  end

  describe "a crash report" do
    test "holds the shape of the last message of a process, and not the message" do
      {:ok, server} = GenServer.start(Stops, :state)
      reference = Process.monitor(server)

      log =
        capture_log(fn ->
          GenServer.cast(server, {:note, "the note that a person typed"})
          assert_receive {:DOWN, ^reference, :process, ^server, _reason}
          # The report goes to the log after the process stops.
          Process.sleep(100)
        end)

      assert log =~ "(RuntimeError) no room"
      assert log =~ "Rescord.LogTest.Stops.handle_cast/2"
      assert log =~ "Last message: {:\"$gen_cast\", {:note, binary}}"
      refute log =~ "typed"
    end

    test "is complete at the level debug, which also writes the state" do
      report = %{label: {:gen_server, :terminate}, last_message: {:note, "typed"}}
      assert Translator.translate(:debug, :error, :report, {:logger, report}) == :none
    end

    test "leaves each other report to the translator of Elixir" do
      assert Translator.translate(:info, :error, :report, {:other, %{}}) == :none
      assert Translator.translate(:info, :error, :format, {~c"text", []}) == :none
    end

    test "holds the shape of the arguments of a task" do
      report = %{
        name: self(),
        starter: self(),
        function: &String.upcase/1,
        args: ["the note that a person typed"],
        reason: {%RuntimeError{message: "no room"}, []},
        process_label: :undefined
      }

      assert {:ok, text, _metadata} =
               Translator.translate(
                 :info,
                 :error,
                 :report,
                 {{Task.Supervisor, :terminating}, report}
               )

      text = IO.iodata_to_binary(text)
      assert text =~ "Args: [binary]"
      refute text =~ "typed"
    end
  end
end
