defmodule Rescord.Attention do
  @moduledoc """
  What needs somebody now in an organisation (ADR 0065): the first page of
  the organisation shows it.

  Each domain says what needs somebody in its own part, with a function
  `attention`, as each domain gives its own grants (ADR 0024) and its own
  changes to the timeline (ADR 0035). This module asks each of them, and
  knows nothing of what a row means:

    * `Rescord.Tasks.attention/2` - the tasks that are overdue, and the
      tasks of today that are still due;
    * `Rescord.Inventory.attention/2` - the items to count, to order, or
      with stock that is past its expiry date or expires soon;
    * `Rescord.Residents.attention/2` - the residents that are late back,
      and the ones that are expected;
    * `Rescord.Locations.attention/2` - the locations over their capacity;
    * `Rescord.Transfers.attention/3` - the transfers and the partner
      requests that wait for an answer.

  Three rules hold for each of them.

    * **A person sees what they can read.** Each read runs as the actor, so
      the policies decide.
    * **A person sees what they can act on.** A row is there only for a
      role with the power that puts it right. What a role can only look at
      does not need that person.
    * **A list has a limit.** A part gives at most `limit/0` rows, and a
      total that counts all of them.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Rescord.Tasks,
      Rescord.Inventory,
      Rescord.Residents,
      Rescord.Locations,
      Rescord.Transfers
    ]

  alias Rescord.{Inventory, Locations, Residents, Tasks, Transfers}

  # The rows that a part shows. The total of the part counts the others.
  @limit 8

  @typedoc """
  One thing that needs somebody: its kind, the record that a person opens
  to act on it, and what else its domain says about it.
  """
  @type row :: %{
          required(:kind) => atom,
          required(:record) => Ash.Resource.record(),
          optional(atom) => term
        }

  @typedoc """
  A part of the organisation with something that needs somebody: its rows,
  at most `limit/0` of them, and the number of all such things in it.
  """
  @type part :: %{
          part: :tasks | :inventory | :residents | :housing | :transfers,
          rows: [row, ...],
          total: pos_integer
        }

  @doc """
  The domains that `parts/2` reads. The first page listens for a change of
  each (ADR 0096).
  """
  @spec domains() :: [module]
  def domains, do: [Tasks, Inventory, Residents, Locations, Transfers]

  @doc "The most rows that a part shows."
  @spec limit() :: pos_integer
  def limit, do: @limit

  @doc """
  The parts of an organisation that have something that needs the person
  `:actor`, whose role there is `:role`, at the instant `:now`. A part with
  nothing is not in the list, so an empty list says that nothing needs
  that person now.

  The role decides only which rows a person can act on. Each read still
  runs as the actor, so a role that the caller got wrong shows no record
  that the policies refuse.
  """
  @spec parts(Ash.Resource.record(), keyword) :: [part]
  def parts(organisation, opts) do
    role = Keyword.fetch!(opts, :role)

    scoped = [
      actor: Keyword.fetch!(opts, :actor),
      tenant: organisation,
      now: Keyword.get(opts, :now, DateTime.utc_now()),
      limit: @limit
    ]

    for {part, read} <- [
          tasks: fn -> Tasks.attention(role, scoped) end,
          inventory: fn -> Inventory.attention(role, scoped) end,
          residents: fn -> Residents.attention(role, scoped) end,
          housing: fn -> Locations.attention(role, scoped) end,
          transfers: fn -> Transfers.attention(role, organisation, scoped) end
        ],
        # A read that fails is a fault of Rescord, and not an empty part.
        {:ok, found} = read.(),
        found.rows != [] do
      %{part: part, rows: found.rows, total: found.total}
    end
  end

  @doc "The number of things that need somebody, in all the parts."
  @spec total([part]) :: non_neg_integer
  def total(parts), do: parts |> Enum.map(& &1.total) |> Enum.sum()
end
