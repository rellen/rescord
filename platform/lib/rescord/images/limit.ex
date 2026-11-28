defmodule Rescord.Images.Limit do
  @moduledoc """
  Lets only a few photos go through libvips at the same time (ADR 0056).

  libvips decodes a photo to turn it, and a photo of 48 million pixels from
  a phone takes about 150 MB while it works. Ten such photos at once can
  take more memory than a small server has. `run/2` runs the work in a
  process of its own, which waits for one of the `slots` of the server:

    * A slot goes to the work that has waited longest.
    * Work that waits longer than `wait` milliseconds does not run, and
      `run/2` returns `{:error, :busy}`.
    * The process holds its slot until it is gone, and `run/2` returns
      after that. So what libvips holds for a photo is free again before
      the next photo starts: an image of libvips lives until the process
      that made it collects its garbage or ends.
    * The process is linked to its caller. A caller that stops takes its
      work with it, and work that fails stops its caller, as it would with
      no process between them.

  The configuration of `:rescord, Rescord.Images.Limit` sets `slots` and
  `wait`; the environment variable `RESCORD_PHOTO_SLOTS` sets `slots` on a
  server. The application starts the server.
  """

  use GenServer

  require Logger

  @default_slots 2
  @default_wait :timer.seconds(30)

  @doc "The slots and the wait of the configuration, with their defaults."
  @spec settings() :: %{slots: pos_integer, wait: non_neg_integer}
  def settings do
    config = Application.get_env(:rescord, __MODULE__, [])

    %{
      slots: Keyword.get(config, :slots, @default_slots),
      wait: Keyword.get(config, :wait, @default_wait)
    }
  end

  @doc """
  Starts the server. The options are `:slots` and `:wait`, from `settings/0`
  when they are not given, and `:name`, this module by default.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Map.merge(settings(), Map.new(opts)), name: name)
  end

  @doc """
  Runs `work` in a process of its own when a slot is free, and returns what
  it returns, or `{:error, :busy}` when no slot came free in time. `server`
  is the name or the pid of the server.
  """
  @spec run((-> result), GenServer.server()) :: result | {:error, :busy} when result: term
  def run(work, server \\ __MODULE__) when is_function(work, 0) do
    caller = self()
    tag = make_ref()

    {worker, monitor} =
      Process.spawn(
        fn ->
          # The server always answers: at once, when a slot comes free, or
          # when the wait is over. So the call needs no timeout of its own.
          case GenServer.call(server, :take, :infinity) do
            :ok -> send(caller, {tag, work.()})
            :busy -> send(caller, {tag, {:error, :busy}})
          end
        end,
        [:link, :monitor]
      )

    receive do
      {^tag, answer} ->
        # The slot is free when the worker is gone, and not before.
        receive do
          {:DOWN, ^monitor, :process, ^worker, _reason} -> answer
        end

      {:DOWN, ^monitor, :process, ^worker, reason} ->
        # Only a caller that traps exits comes here: the link stops another.
        exit(reason)
    end
  end

  @impl true
  def init(%{slots: slots, wait: wait})
      when is_integer(slots) and slots > 0 and is_integer(wait) and wait >= 0 do
    {:ok, %{slots: slots, wait: wait, holders: MapSet.new(), waiting: :queue.new()}}
  end

  @impl true
  def handle_call(:take, {pid, _tag} = from, state) do
    monitor = Process.monitor(pid)

    if MapSet.size(state.holders) < state.slots do
      {:reply, :ok, %{state | holders: MapSet.put(state.holders, monitor)}}
    else
      timer = Process.send_after(self(), {:expire, monitor}, state.wait)
      {:noreply, %{state | waiting: :queue.in({monitor, from, timer}, state.waiting)}}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    if MapSet.member?(state.holders, monitor) do
      {:noreply, pass_on(%{state | holders: MapSet.delete(state.holders, monitor)})}
    else
      # A process that stopped while it waited leaves the queue.
      case take_out(state.waiting, monitor) do
        {{^monitor, _from, timer}, rest} ->
          Process.cancel_timer(timer)
          {:noreply, %{state | waiting: rest}}

        nil ->
          {:noreply, state}
      end
    end
  end

  # A timer that fires after its process took a slot or stopped finds nothing.
  def handle_info({:expire, monitor}, state) do
    case take_out(state.waiting, monitor) do
      {{^monitor, from, _timer}, rest} ->
        Process.demonitor(monitor, [:flush])

        :telemetry.execute([:rescord, :photos, :refused], %{count: 1}, %{})

        Logger.warning(
          "A photo waited #{state.wait} ms for one of the #{state.slots} slots of libvips, " <>
            "and did not go through. RESCORD_PHOTO_SLOTS sets the number of the slots."
        )

        GenServer.reply(from, :busy)
        {:noreply, %{state | waiting: rest}}

      nil ->
        {:noreply, state}
    end
  end

  # A slot is free: it goes to the process that has waited longest.
  defp pass_on(state) do
    case :queue.out(state.waiting) do
      {{:value, {monitor, from, timer}}, rest} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, :ok)
        %{state | holders: MapSet.put(state.holders, monitor), waiting: rest}

      {:empty, _queue} ->
        state
    end
  end

  defp take_out(queue, monitor) do
    waiters = :queue.to_list(queue)

    case Enum.split_with(waiters, fn {waiter, _from, _timer} -> waiter == monitor end) do
      {[found], rest} -> {found, :queue.from_list(rest)}
      {[], _rest} -> nil
    end
  end
end
