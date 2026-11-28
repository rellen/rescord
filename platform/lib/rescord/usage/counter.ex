defmodule Rescord.Usage.Counter do
  @moduledoc """
  The counts of this node in memory, until `Rescord.Usage.flush/0` writes
  them to the database (ADR 0098).

  `add/1` is one `:ets.update_counter/4` on a public table, so that a count
  costs a page or an action next to nothing, and no process waits for
  another. This process owns the table, and each minute it writes the
  counts and reads the mode again, which another node can have changed. It
  writes what is left when the server stops.

  With `auto?: false` in `config :rescord, Rescord.Usage.Counter` (the
  tests) it reads no settings and writes nothing by itself: a test calls
  `Rescord.Usage.flush/0`.
  """

  use GenServer

  @table __MODULE__
  @every :timer.minutes(1)

  @typedoc "A key of the table: the day, the feature, the kind and the item."
  @type key :: {Date.t(), atom, atom, String.t()}

  def start_link(arg), do: GenServer.start_link(__MODULE__, arg, name: __MODULE__)

  @doc """
  Adds one to a count of today. It does nothing when the table is not
  there, as before the start: a count is never worth a fault.
  """
  @spec add({atom, atom, String.t()}) :: :ok
  def add({feature, kind, item}) do
    key = {Date.utc_today(), feature, kind, item}
    :ets.update_counter(@table, key, 1, {key, 0})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Takes each count out of the table, as `{key, number}`."
  @spec take_all() :: [{key, pos_integer}]
  def take_all do
    @table
    |> :ets.select([{{:"$1", :_}, [], [:"$1"]}])
    |> Enum.flat_map(&:ets.take(@table, &1))
    |> Enum.filter(fn {_key, number} -> number > 0 end)
  rescue
    ArgumentError -> []
  end

  @doc "Puts counts back that could not be written."
  @spec put_back([{key, pos_integer}]) :: :ok
  def put_back(counts) do
    for {key, number} <- counts, do: :ets.update_counter(@table, key, number, {key, 0})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Empties the table: the mode is `off`."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl true
  def init(_arg) do
    Process.flag(:trap_exit, true)

    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      write_concurrency: true,
      decentralized_counters: true
    ])

    auto? = Keyword.get(Application.get_env(:rescord, __MODULE__, []), :auto?, true)
    if auto?, do: {:ok, %{auto?: true}, {:continue, :mode}}, else: {:ok, %{auto?: false}}
  end

  @impl true
  def handle_continue(:mode, state) do
    Rescord.Usage.read_mode()
    {:noreply, schedule(state)}
  end

  @impl true
  def handle_info(:flush, state) do
    Rescord.Usage.read_mode()
    Rescord.Usage.flush()
    {:noreply, schedule(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{auto?: true}), do: Rescord.Usage.flush()
  def terminate(_reason, _state), do: :ok

  defp schedule(state) do
    Process.send_after(self(), :flush, @every)
    state
  end
end
