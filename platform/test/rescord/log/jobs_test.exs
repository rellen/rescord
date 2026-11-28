defmodule Rescord.Log.JobsTest do
  @moduledoc """
  Holds the lines of the log for the jobs of Oban (ADR 0077): a job that
  fails writes a line, and the line holds no argument of the job.
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureLog

  require Logger

  defmodule Worker do
    @moduledoc false
    use Oban.Worker, queue: :default, max_attempts: 2

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"how" => "raise"}}), do: raise("no room for fern@example.org")
    def perform(%Oban.Job{args: %{"how" => "error"}}), do: {:error, "fern@example.org"}
    def perform(%Oban.Job{args: %{"how" => "cancel"}}), do: {:cancel, :not_needed}

    def perform(%Oban.Job{args: %{"how" => "say"}}) do
      Logger.warning("the job says a thing")
      :ok
    end
  end

  setup do
    before = Logger.metadata()
    on_exit(fn -> Logger.reset_metadata(before) end)
  end

  defp run(arguments) do
    {:ok, job} = Oban.insert(Worker.new(arguments))

    log =
      capture_log([format: "$metadata[$level] $message\n", metadata: Rescord.Log.fields()], fn ->
        Oban.drain_queue(queue: :default)
      end)

    {job, log}
  end

  test "a job that raises writes a warning while Oban tries it again" do
    {job, log} = run(%{"how" => "raise", "email" => "fern@example.org"})

    assert log =~
             "[warning] The job #{job.id} of Rescord.Log.JobsTest.Worker failed on try 1 of 2"

    assert log =~ "and runs again later: RuntimeError"
    assert log =~ "Rescord.Log.JobsTest.Worker.perform/1"
    assert log =~ "job=#{job.id} worker=Rescord.Log.JobsTest.Worker queue=default attempt=1"
    refute log =~ "fern"
  end

  test "a job that returns an error writes the shape of the error" do
    {_job, log} = run(%{"how" => "error"})

    assert log =~ "and runs again later: Oban.PerformError(reason: {:error, binary})"
    refute log =~ "fern"
  end

  test "the last try of a job writes an error" do
    {:ok, job} = Oban.insert(Worker.new(%{"how" => "error"}, max_attempts: 1))
    log = capture_log(fn -> Oban.drain_queue(queue: :default) end)

    assert log =~ "[error] The job #{job.id} of Rescord.Log.JobsTest.Worker failed on try 1 of 1"
    assert log =~ "the last one: Oban.PerformError"
  end

  test "a job that its worker cancels writes a warning" do
    {job, log} = run(%{"how" => "cancel"})

    assert log =~
             "[warning] The job #{job.id} of Rescord.Log.JobsTest.Worker stopped as cancelled: " <>
               "{:cancel, :not_needed}"
  end

  test "a line that a job writes names the job and the organisation of its tenant" do
    id = Ash.UUID.generate()
    {job, log} = run(%{"how" => "say", "tenant" => "org_" <> id})

    assert log =~ "organisation=#{id} job=#{job.id} worker=Rescord.Log.JobsTest.Worker"
    assert log =~ "the job says a thing"
  end

  test "a job that works writes no line" do
    {:ok, _job} = Oban.insert(Worker.new(%{"how" => "say"}))

    log =
      capture_log(fn ->
        assert %{success: 1} = Oban.drain_queue(queue: :default)
      end)

    assert log =~ "the job says a thing"
    refute log =~ "The job"
  end
end
