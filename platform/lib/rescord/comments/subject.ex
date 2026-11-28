defmodule Rescord.Comments.Subject do
  @moduledoc """
  The record that a comment or a follow is on: `{kind, id}`, where the kind
  is one of `kinds/0`. A comment holds it in one of five columns, and the
  database holds that exactly one of them has a value.

  `readable?/2` reads the record as the actor of the options, through its
  domain: a person writes on a record only when they can read it. A
  transfer is in the shared schema and has two organisations, so it is read
  with `Rescord.Transfers.transfer_of/3`, for the organisation of the
  request.
  """

  alias Rescord.{Expenses, Journal, Residents, Tasks, Transfers}

  @type kind :: :resident | :task | :expense | :transfer | :journal_entry
  @type t :: {kind, Ecto.UUID.t()}

  @columns [
    resident: :resident_id,
    task: :task_id,
    expense: :expense_id,
    transfer: :transfer_id,
    journal_entry: :journal_entry_id
  ]

  @doc "The kinds of record that take comments."
  @spec kinds() :: [kind]
  def kinds, do: Keyword.keys(@columns)

  @doc "The columns of the kinds, in the order of `kinds/0`."
  @spec columns() :: [atom]
  def columns, do: Keyword.values(@columns)

  @doc "The column of a kind."
  @spec column(kind) :: atom
  def column(kind)
      when is_map_key(%{resident: 1, task: 1, expense: 1, transfer: 1, journal_entry: 1}, kind),
      do: Keyword.fetch!(@columns, kind)

  @doc "The record of a comment or a follow, as `{kind, id}`, or `nil` when it names none."
  @spec of(map) :: t | nil
  def of(record) do
    Enum.find_value(@columns, fn {kind, column} ->
      case Map.get(record, column) do
        nil -> nil
        id -> {kind, id}
      end
    end)
  end

  @doc """
  Whether the actor of `opts` can read the record, in the organisation that
  is the tenant of `opts`.
  """
  @spec readable?(t, keyword) :: boolean
  def readable?({kind, id}, opts) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> match?({:ok, %{}}, read(kind, id, opts))
      :error -> false
    end
  end

  def readable?(_subject, _opts), do: false

  defp read(:resident, id, opts), do: Residents.resident(id, opts)
  defp read(:task, id, opts), do: Tasks.task(id, opts)
  defp read(:expense, id, opts), do: Expenses.expense(id, opts)
  defp read(:journal_entry, id, opts), do: Journal.entry(id, opts)

  defp read(:transfer, id, opts) do
    case Keyword.get(opts, :tenant) do
      %{id: _} = organisation ->
        Transfers.transfer_of(organisation, id, Keyword.take(opts, [:actor, :authorize?]))

      _no_organisation ->
        {:ok, nil}
    end
  end
end
