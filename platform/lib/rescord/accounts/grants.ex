defmodule Rescord.Accounts.Grants do
  @moduledoc """
  What a role can do (`docs/architecture.md`, "Policies and roles", and
  ADR 0040).

  A grant names a resource, an action and a scope. A scope is a named filter
  on the resource: a role can run the action on the records that the scope
  holds. A role appears in no policy. The policy of a resource is the check
  `Rescord.Accounts.Checks.Granted`, which reads the role of the member of
  the actor in the organisation, and the grants of that role.

  ## Powers

  A role is a record of the organisation, `Rescord.Accounts.Role`, with a
  list of powers. A power is one area of work, such as `:journal`, and it
  holds the grants of the actions of that work. Each role also has the
  reads: each member reads what the organisation has. A role with no power
  reads, and changes nothing.

  Each organisation starts with two roles. `default_powers/1` gives their
  powers: `:administrator` has each power, and `:member` has the powers of
  a member of ADR 0021. A test holds those two to the grants of ADR 0021.
  `grants/1` also takes the keys `:administrator` and `:member`, for a page
  and a test that ask about one of those two roles.

  A root user is outside the grants: a root user can do anything.

  ## The grants of another domain

  This module holds the powers of the accounts. Another domain holds its own
  powers, in a module that is a source of grants (ADR 0024): it has
  `reads/0`, `powers/0`, a map from a power to its grants, and `filter/2`,
  the filter of each scope of its own other than `:all`. The configuration
  names the sources, in `config :rescord, :grant_sources`. This module thus
  names no resource of another domain.
  """

  @doc "The grants that each role has: the reads of the domain."
  @callback reads() :: [{module, atom, atom}]

  @doc "The grants of each power of the domain."
  @callback powers() :: %{atom => [{module, atom, atom}]}

  @doc "The filter of a scope of a resource of the domain, other than `:all`."
  @callback filter(module, atom) :: Ash.Expr.t() | boolean | nil

  @optional_callbacks filter: 2

  require Ash.Expr

  alias Rescord.Accounts.{Member, Organisation, Role}

  @type role :: Ash.Resource.record() | :administrator | :member | nil
  @type scope :: :all | atom

  # Each power, in the order of the page of the roles.
  @power_keys [
    :members,
    :roles,
    :settings,
    :lists,
    :residents,
    :remove_residents,
    :placements,
    :locations,
    :journal,
    :correct_journal,
    :tasks,
    :routines,
    :stock,
    :inventory,
    :transfers,
    :export,
    :calendar
  ]

  # The powers of a member of ADR 0021, and the calendar feed of ADR 0074.
  @member_powers [:residents, :placements, :journal, :tasks, :stock, :calendar]

  @reads [{Member, :read, :all}, {Role, :read, :all}]

  @powers %{
    members: [
      {Member, :invite_member, :all},
      {Member, :set_role, :members},
      {Member, :make_administrator, :members},
      # A person who changes the members removes a member who does not.
      {Member, :remove, :members}
    ],
    roles: [{Role, :define, :all}, {Role, :revise, :all}, {Role, :remove, :all}],
    # The settings of the organisation itself (ADR 0026).
    settings: [
      {Organisation, :set_time_zone, :all},
      {Organisation, :set_task_days_ahead, :all},
      {Organisation, :set_transfer_parts, :all}
    ],
    # The export of the data of the organisation (ADR 0054).
    export: [{Organisation, :export, :all}]
  }

  # The sources of the other domains. A module name is an atom, so this is
  # no use of those domains when this module compiles.
  @sources Application.compile_env(:rescord, :grant_sources, [])

  @doc "The sources of grants of the other domains."
  @spec sources() :: [module]
  def sources, do: @sources

  @doc "Each power, in the order of the page of the roles."
  @spec power_keys() :: [atom]
  def power_keys, do: @power_keys

  @doc "The keys of the two roles that each organisation has."
  @spec roles() :: [:administrator | :member]
  def roles, do: [:administrator, :member]

  @doc "The powers of one of the two roles that each organisation has."
  @spec default_powers(:administrator | :member) :: [atom]
  def default_powers(:administrator), do: @power_keys
  def default_powers(:member), do: @member_powers

  @doc "The grants of each power, of the accounts and of each source."
  @spec powers() :: %{atom => [{module, atom, scope}]}
  def powers do
    Enum.reduce(@sources, @powers, fn source, all ->
      Map.merge(all, source.powers(), fn _key, one, other -> one ++ other end)
    end)
  end

  @doc "The grants that each role has: the reads of the accounts and of each source."
  @spec reads() :: [{module, atom, scope}]
  def reads, do: @reads ++ Enum.flat_map(@sources, & &1.reads())

  @doc """
  The grants of a role, each as `{resource, action, scope}`: the reads, and
  the grants of its powers. A user who is not a member has no role, and no
  grant.
  """
  @spec grants(role | term) :: [{module, atom, scope}]
  def grants(%Role{powers: powers}), do: grants_of(powers)
  def grants(key) when key in [:administrator, :member], do: grants_of(default_powers(key))
  def grants(_no_role), do: []

  defp grants_of(powers) do
    all = powers()
    reads() ++ Enum.flat_map(powers, &Map.get(all, &1, []))
  end

  @doc """
  The scope in which `role` can run `action` of `resource`, or `:none`. When
  two powers give the action, the wider scope counts: `:all` is the widest.
  """
  @spec scope(role | term, module, atom) :: {:ok, scope} | :none
  def scope(role, resource, action) do
    scopes = for {^resource, ^action, scope} <- grants(role), uniq: true, do: scope

    cond do
      scopes == [] -> :none
      :all in scopes -> {:ok, :all}
      true -> {:ok, hd(scopes)}
    end
  end

  @doc """
  Whether `role` can run `action` on one record that it has in hand, in the
  organisation `tenant`. A page uses this to show a button only where the
  action would work. The policy still decides when the action runs.
  """
  @spec allows?(role | term, module, atom, Ash.Resource.record(), term) :: boolean
  def allows?(role, resource, action, record, tenant) do
    case scope(role, resource, action) do
      :none ->
        false

      {:ok, :all} ->
        true

      # The roles are in the database, so this scope is not an expression
      # that Ash evaluates in memory.
      {:ok, :members} when resource == Member ->
        record.role_id not in managers(tenant)

      {:ok, scope} ->
        Ash.Expr.eval(filter(resource, scope, tenant), record: record) == {:ok, true}
    end
  end

  @doc """
  The filter of a scope of a resource, in the organisation `tenant`. `:all`
  holds each record.

  The scope `:members` of a member holds each member whose role does not
  have the power `:members`: a person who changes the members does not
  change another person who can.
  """
  @spec filter(module, scope, term) :: Ash.Expr.t() | boolean
  def filter(resource, scope, tenant \\ nil)
  def filter(_resource, :all, _tenant), do: true

  def filter(Member, :members, nil), do: false

  def filter(Member, :members, tenant) do
    managers = managers(tenant)
    Ash.Expr.expr(role_id not in ^managers)
  end

  def filter(resource, scope, _tenant) do
    Enum.find_value(@sources, fn source ->
      if function_exported?(source, :filter, 2), do: source.filter(resource, scope)
    end)
  end

  # The ids of the roles of an organisation that have the power `:members`.
  defp managers(nil), do: []

  defp managers(tenant) do
    Role
    |> Ash.Query.select([:id, :powers])
    |> Ash.read!(tenant: tenant, authorize?: false)
    |> Enum.filter(&(:members in &1.powers))
    |> Enum.map(& &1.id)
  end
end
