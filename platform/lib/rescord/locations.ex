defmodule Rescord.Locations do
  @moduledoc """
  The locations of an organisation, and who lives where (`docs/domain.md`,
  section 5.5, and ADR 0029).

  A location can be inside any other location, and a placement says that a
  resident or a group lives in a location for a time. Each resource here is
  temporal (ADR 0012): pass `as_of:` in the options of a function to read
  the housing as it was, or to write a move at the instant that it happened.

  ## Where a resident lives

  A resident with a placement of its own lives there. In each other case it
  lives with each of its groups that has a placement. `home/2` gives the
  answer for one resident, and `tree/1` gives it for the whole housing.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain, AshAi]

  require Ash.Query

  alias Rescord.Locations.{Location, LocationParent, Placement}
  alias Rescord.Residents

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Lists, Rescord.Residents]
  end

  paper_trail do
    include_versions? true
  end

  # The tools of the assistant (ADR 0069). A tool here is no tool of Ruby
  # until `Rescord.Ruby.Catalogue` names it, and it runs as the member,
  # with the policy of the action.
  tools do
    tool :find_locations, Rescord.Locations.Location, :read do
      description """
      Finds the places of the rescue (pens, rooms, paddocks and so on) by
      name. Use it to turn a place that the person said into a location, and
      then `housing` for who lives there. A missing field means that nothing
      is recorded.
      """

      select [:id, :name, :capacity]
      filterable_fields([:name])
      sortable_fields([:name])
      aggregatable_fields([])
      action_parameters([:filter, :sort, :limit, :result_type])
      annotations(read_only_hint: true)
    end
  end

  resources do
    resource Rescord.Locations.Location do
      define :locations, action: :read
      define :location, action: :read, get_by: [:id], not_found_error?: false
      define :add_location, action: :add
      define :revise_location, action: :revise
      define :close_location, action: :close
    end

    resource Rescord.Locations.LocationParent do
      define :location_parents, action: :read
      define :put_inside, action: :put_inside
      define :take_out, action: :take_out
    end

    resource Rescord.Locations.Placement do
      define :placements, action: :read
      define :place, action: :place
      define :move_placement, action: :move
      define :finish_placement, action: :finish
    end
  end

  @doc """
  Puts a location inside another one, or inside none when `parent_id` is
  `nil`. It ends the tie that the location has, and makes the new one, in
  one transaction.
  """
  def move_location(%Location{} = location, parent_id, opts \\ []) do
    # One correlation id for the end of the old tie and the new one (ADR 0101).
    opts = Rescord.Correlation.start(opts)

    # `Ash.transact`, and not a transaction of the repo: it sends the
    # notifications of the two writes after the commit (ADR 0096).
    Ash.transact(
      [LocationParent],
      fn ->
        with {:ok, tie} <- tie_of(location.id, opts),
             :ok <- end_tie(tie, opts) do
          new_tie(location.id, parent_id, opts)
        end
      end,
      tenant: opts[:tenant]
    )
    |> case do
      {:ok, {:ok, result}} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  defp tie_of(location_id, opts) do
    LocationParent |> Ash.Query.filter(location_id == ^location_id) |> Ash.read_one(opts)
  end

  defp end_tie(nil, _opts), do: :ok
  defp end_tie(tie, opts), do: take_out(tie, opts)

  defp new_tie(_location_id, nil, _opts), do: {:ok, nil}

  defp new_tie(location_id, parent_id, opts),
    do: put_inside(%{location_id: location_id, parent_id: parent_id}, opts)

  @doc """
  Makes a resident or a group live in a location. `subject` is
  `{:resident, id}` or `{:group, id}`. A subject with a placement moves, and
  one with none gets a placement.
  """
  def settle({kind, id}, location_id, opts \\ []) when kind in [:resident, :group] do
    key = if kind == :resident, do: :resident_id, else: :group_id

    case placement_of(key, id, opts) do
      {:ok, nil} -> place(%{key => id, location_id: location_id}, opts)
      {:ok, %Placement{location_id: ^location_id} = placement} -> {:ok, placement}
      {:ok, placement} -> move_placement(placement, %{location_id: location_id}, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp placement_of(:resident_id, id, opts),
    do: Placement |> Ash.Query.filter(resident_id == ^id) |> Ash.read_one(opts)

  defp placement_of(:group_id, id, opts),
    do: Placement |> Ash.Query.filter(group_id == ^id) |> Ash.read_one(opts)

  @doc """
  Where a resident lives: a list of `%{location: location, with: with}`.
  `with` is `:own` for a placement of its own, and the group for a placement
  of a group of the resident. The list is empty when the resident has no
  place.
  """
  def home(resident_id, opts \\ []) do
    load = [load: [location: [kind: [:label]]]]

    with {:ok, own} <- placement_of(:resident_id, resident_id, load ++ opts) do
      if own do
        {:ok, [%{location: own.location, with: :own, placement: own}]}
      else
        {:ok, group_homes(resident_id, load ++ opts, opts)}
      end
    end
  end

  @doc "The placement of a group, with its location, or `nil`."
  def group_home(group_id, opts \\ []) do
    placement_of(:group_id, group_id, [load: [location: [kind: [:label]]]] ++ opts)
  end

  defp group_homes(resident_id, read_opts, opts) do
    relations = Residents.relations(resident_id, opts)

    for {_membership, group} <- (relations && relations.groups) || [],
        {:ok, %Placement{} = placement} <- [placement_of(:group_id, group.id, read_opts)] do
      %{location: placement.location, with: group, placement: placement}
    end
  end

  @doc """
  The housing of the organisation as a tree: the locations that are inside
  no other one, each with the locations inside it.

  A node is a map:

    * `location` - the location, with the label of its kind;
    * `children` - the nodes of the locations inside it, in the order of
      their names;
    * `residents` - the placements of the residents that live here by a
      placement of their own;
    * `groups` - the placements of the groups that live here, each as
      `{placement, group, residents}`, with the members that live with the
      group;
    * `count` - the number of residents that live here or inside;
    * `over?` - whether `count` is more than the capacity.
  """
  def tree(opts \\ []) do
    with {:ok, groups} <- Residents.groups_with_facts(opts), do: tree_with(groups, opts)
  end

  # The tree, with the groups that the caller read: each with its members.
  defp tree_with(groups, opts) do
    with {:ok, locations} <- locations([load: [kind: [:label]]] ++ opts),
         {:ok, ties} <- location_parents(opts),
         {:ok, placements} <- placements([load: [resident: [:name]]] ++ opts) do
      groups = Map.new(groups, &{&1.id, &1})

      # A placement of a resident that the actor cannot read, such as one that
      # an administrator removed, is not in the housing.
      placements = Enum.reject(placements, &(&1.resident_id && is_nil(&1.resident)))
      apart = for %{resident_id: id} when not is_nil(id) <- placements, into: MapSet.new(), do: id
      here = Enum.group_by(placements, & &1.location_id)
      ids = MapSet.new(locations, & &1.id)

      # A tie to a location that the actor does not read is no tie here.
      parent_of =
        for tie <- ties, tie.parent_id in ids, into: %{}, do: {tie.location_id, tie.parent_id}

      children = Enum.group_by(locations, &Map.get(parent_of, &1.id))

      {:ok, Enum.map(sorted(children[nil]), &node(&1, children, here, groups, apart))}
    end
  end

  defp sorted(nil), do: []
  defp sorted(locations), do: Enum.sort_by(locations, & &1.name)

  defp node(location, children, here, groups, apart) do
    placements = Map.get(here, location.id, [])

    residents =
      placements |> Enum.filter(& &1.resident_id) |> Enum.sort_by(&(&1.resident.name || ""))

    with_groups =
      for placement <- placements, group = groups[placement.group_id], not is_nil(group) do
        # A member with a placement of its own lives there, and not here.
        {placement, group, Enum.reject(group.members, &(&1.resident_id in apart))}
      end

    inside = Enum.map(sorted(children[location.id]), &node(&1, children, here, groups, apart))

    count =
      length(residents) +
        Enum.sum(Enum.map(with_groups, fn {_placement, _group, members} -> length(members) end)) +
        Enum.sum(Enum.map(inside, & &1.count))

    %{
      location: location,
      children: inside,
      residents: residents,
      groups: with_groups,
      count: count,
      over?: is_integer(location.capacity) and count > location.capacity
    }
  end

  @doc """
  The locations that need somebody now (ADR 0065): each location with more
  residents in it than its capacity, as `tree/1` counts them, the outer
  location before the ones inside it.

  Returns `%{rows: rows, total: total}`. A row is
  `%{kind: :over_capacity, record: location, count: count}`. There are at
  most `:limit` rows, and `total` counts each such location. A role that
  cannot move a resident or a group gets no row: it can do nothing about
  one.
  """
  @spec attention(term, keyword) :: {:ok, %{rows: [map], total: non_neg_integer}} | {:error, term}
  def attention(role, opts \\ []) do
    {limit, opts} = Keyword.pop(opts, :limit, 8)
    opts = Keyword.delete(opts, :now)

    with true <- role_can?(role, :placement, :move),
         # Most housing has no capacity: then no location is over it.
         {:ok, [_ | _]} <- Location |> Ash.Query.filter(not is_nil(capacity)) |> Ash.read(opts),
         # The count needs the members of each group, and not its words.
         {:ok, groups} <- Residents.groups(Keyword.put(opts, :load, [:members])),
         {:ok, tree} <- tree_with(groups, opts) do
      rows =
        for {%{over?: true} = node, _depth} <- flat(tree) do
          %{kind: :over_capacity, record: node.location, count: node.count}
        end

      {:ok, %{rows: Enum.take(rows, limit), total: length(rows)}}
    else
      {:error, error} -> {:error, error}
      _nothing -> {:ok, %{rows: [], total: 0}}
    end
  end

  @doc "The node of one location in the tree, or `nil`."
  def find(nodes, id) do
    Enum.find_value(nodes, fn node ->
      if node.location.id == id, do: node, else: find(node.children, id)
    end)
  end

  @doc "Each node of a tree in one list, each with its depth: `{node, depth}`."
  def flat(nodes, depth \\ 0) do
    Enum.flat_map(nodes, &[{&1, depth} | flat(&1.children, depth + 1)])
  end

  @doc """
  The changes that Rescord recorded about where a resident lives, in the
  order of time: each placement of its own, each move and each end. Each
  one is a change of `Rescord.History` with the `subject` `:placement`.
  The placements of the groups of the resident are not here.

  Returns `[]` when the actor can read no such resident: the policy of the
  versions refuses each actor (ADR 0063), so the resident decides.
  """
  def changes(resident_id, opts \\ []) do
    case Residents.resident(resident_id, opts) do
      {:ok, %{id: ^resident_id}} ->
        Placement
        |> AshPaperTrail.Resource.Info.version_resource()
        |> Ash.Query.filter(resident_id == ^resident_id)
        |> Ash.read!(tenant: opts[:tenant], authorize?: false)
        |> Rescord.History.changes()
        |> Enum.map(&Map.put(&1, :subject, :placement))

      _no_resident ->
        []
    end
  end

  @doc """
  Whether a role can run an action of a resource of this domain at all. A
  page asks this to decide what to show. The policy decides when the action
  runs.
  """
  @spec role_can?(atom | nil, :location | :location_parent | :placement, atom) :: boolean
  def role_can?(role, subject, action) do
    resource =
      case subject do
        :location -> Location
        :location_parent -> LocationParent
        :placement -> Placement
      end

    Rescord.Accounts.granted?(role, resource, action)
  end
end
