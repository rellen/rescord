defmodule Rescord.Images.LimitTest do
  @moduledoc """
  Holds the limit on the photos that go through libvips at once (ADR 0056):
  no more work than the slots at a time, the longest wait first, the end of
  a wait, and a slot that comes back when its process is gone.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Rescord.Images.Limit

  defp limit(opts) do
    start_supervised!({Limit, Keyword.put(opts, :name, nil)})
  end

  # Starts work that tells the test that it runs, and then waits for `:go`.
  defp hold(server, name) do
    test = self()

    Task.async(fn ->
      Limit.run(
        fn ->
          send(test, {:runs, name, self()})

          receive do
            :go -> name
          end
        end,
        server
      )
    end)
  end

  test "work returns what it returns, in a process of its own" do
    server = limit(slots: 1)
    assert Limit.run(fn -> {:ok, 4} end, server) == {:ok, 4}
    refute Limit.run(fn -> self() end, server) == self()
  end

  test "no more work runs at once than the slots" do
    server = limit(slots: 2, wait: 5_000)
    counter = :counters.new(1, [])
    most = :atomics.new(1, [])

    1..12
    |> Task.async_stream(
      fn _n ->
        Limit.run(
          fn ->
            :counters.add(counter, 1, 1)
            now = :counters.get(counter, 1)
            if now > :atomics.get(most, 1), do: :atomics.put(most, 1, now)
            Process.sleep(5)
            :counters.sub(counter, 1, 1)
            now
          end,
          server
        )
      end,
      max_concurrency: 12
    )
    |> Enum.each(fn {:ok, now} -> assert now in 1..2 end)

    assert :atomics.get(most, 1) == 2
  end

  test "a slot goes to the work that has waited longest" do
    server = limit(slots: 1, wait: 5_000)

    first = hold(server, :first)
    assert_receive {:runs, :first, first_worker}

    second = hold(server, :second)
    wait_for_queue(server, 1)
    third = hold(server, :third)
    wait_for_queue(server, 2)

    refute_received {:runs, :second, _worker}
    send(first_worker, :go)
    assert Task.await(first) == :first

    assert_receive {:runs, :second, second_worker}
    refute_received {:runs, :third, _worker}
    send(second_worker, :go)
    assert Task.await(second) == :second

    assert_receive {:runs, :third, third_worker}
    send(third_worker, :go)
    assert Task.await(third) == :third
  end

  test "work that waits too long does not run, and the answer is busy" do
    server = limit(slots: 1, wait: 20)

    first = hold(server, :first)
    assert_receive {:runs, :first, first_worker}

    log =
      capture_log(fn ->
        assert Limit.run(fn -> flunk("the work ran") end, server) == {:error, :busy}
      end)

    assert log =~ "RESCORD_PHOTO_SLOTS"

    # The slot is still good after a wait ended.
    send(first_worker, :go)
    assert Task.await(first) == :first
    assert Limit.run(fn -> :next end, server) == :next
  end

  test "a caller that stops takes its work with it, and the slot comes back" do
    server = limit(slots: 1, wait: 5_000)
    test = self()

    caller =
      spawn(fn ->
        Limit.run(
          fn ->
            send(test, {:runs, self()})
            Process.sleep(:infinity)
          end,
          server
        )
      end)

    assert_receive {:runs, worker}
    monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}

    assert Limit.run(fn -> :next end, server) == :next
  end

  test "a caller that stops while it waits leaves the queue" do
    server = limit(slots: 1, wait: 5_000)

    first = hold(server, :first)
    assert_receive {:runs, :first, first_worker}

    waiter = spawn(fn -> Limit.run(fn -> :never end, server) end)
    wait_for_queue(server, 1)
    Process.exit(waiter, :kill)
    wait_for_queue(server, 0)

    send(first_worker, :go)
    assert Task.await(first) == :first
  end

  test "work that fails stops its caller, and the slot comes back" do
    server = limit(slots: 1, wait: 5_000)

    {caller, monitor} =
      spawn_monitor(fn -> Limit.run(fn -> exit(:broken) end, server) end)

    assert_receive {:DOWN, ^monitor, :process, ^caller, :broken}
    assert Limit.run(fn -> :next end, server) == :next
  end

  test "the server starts with the slots and the wait of the configuration" do
    assert %{slots: slots, wait: wait} = Limit.settings()
    assert is_integer(slots) and slots > 0
    assert is_integer(wait) and wait > 0
    assert %{slots: ^slots, wait: ^wait} = :sys.get_state(Limit)
  end

  defp wait_for_queue(server, length) do
    waiting? = fn -> :queue.len(:sys.get_state(server).waiting) == length end

    assert Shoddy.Tests.eventually(waiting?, timeout: 1_000, interval: 5),
           "the queue never had #{length} waiters"
  end
end
