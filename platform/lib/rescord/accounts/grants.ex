defmodule Rescord.Accounts.Grants do
  @moduledoc """
  What a role can do (`docs/architecture.md`, "Policies and roles").

  A grant names a resource, an action and a scope. A scope is a named filter
  on the resource: a role can run the action on the records that the scope
  holds. A role appears in no policy. The policy of a resource is the check
  `Rescord.Accounts.Checks.Granted`, which reads the grants of the role of
  the actor in the organisation.

  A root user is outside the grants: a root user can do anything.

  The roles and their grants are in code for now. When an organisation
  needs roles of its own, they move to the database (ADR 0021).

  ## The grants of another domain

  This module holds the grants for the members. Another domain holds its own
  grants, in a module that is a source of grants (ADR 0024): it has
  `grants/0`, a map from a role to its grants, and `filter/2`, the filter of
  each scope of its own other than `:all`. The configuration names the
  sources, in `config :rescord, :grant_sources`. This module thus names no
  resource of another domain, and that domain can use the check
  `Rescord.Accounts.Checks.Granted`.
  """

  @doc "The grants of each role, for the resources of one domain."
  @callback grants() :: %{optional(atom) => [{module, atom, atom}]}

  @doc "The filter of a scope of a resource of the domain, other than `:all`."
  @callback filter(module, atom) :: Ash.Expr.t() | boolean | nil

  @optional_callbacks filter: 2

  require Ash.Expr

  alias Rescord.Accounts.Member

  @type role :: :administrator | :member
  @type scope :: :all | atom

  @grants %{
    administrator: [
      {Member, :read, :all},
      {Member, :invite_member, :all},
      {Member, :make_administrator, :all},
      # An administrator removes a member, and not another administrator.
      {Member, :remove, :members},
      # The settings of the organisation itself (ADR 0026).
      {Rescord.Accounts.Organisation, :set_time_zone, :all},
      {Rescord.Accounts.Organisation, :set_task_days_ahead, :all}
    ],
    member: [
      {Member, :read, :all}
    ]
  }

  # The sources of the other domains. A module name is an atom, so this is
  # no use of those domains when this module compiles.
  @sources Application.compile_env(:rescord, :grant_sources, [])

  @doc "The sources of grants of the other domains."
  @spec sources() :: [module]
  def sources, do: @sources

  @doc "The roles that have grants."
  @spec roles() :: [role]
  def roles, do: Map.keys(@grants)

  @doc "The grants of a role, each as `{resource, action, scope}`."
  @spec grants(role) :: [{module, atom, scope}]
  def grants(role) do
    Map.get(@grants, role, []) ++ Enum.flat_map(@sources, &Map.get(&1.grants(), role, []))
  end

  @doc """
  The scope in which `role` can run `action` of `resource`, or `:none`.
  """
  @spec scope(role | nil, module, atom) :: {:ok, scope} | :none
  def scope(role, resource, action) do
    Enum.find_value(grants(role), :none, fn
      {^resource, ^action, scope} -> {:ok, scope}
      _other -> nil
    end)
  end

  @doc """
  Whether `role` can run `action` on one record that it has in hand. A page
  uses this to show a button only where the action would work. The policy
  still decides when the action runs.
  """
  @spec allows?(role | nil, module, atom, Ash.Resource.record()) :: boolean
  def allows?(role, resource, action, record) do
    with {:ok, scope} <- scope(role, resource, action),
         {:ok, true} <- Ash.Expr.eval(filter(resource, scope), record: record) do
      true
    else
      _no -> false
    end
  end

  @doc """
  The filter of a scope of a resource. `:all` holds each record.
  """
  @spec filter(module, scope) :: Ash.Expr.t() | boolean
  def filter(_resource, :all), do: true
  def filter(Member, :members), do: Ash.Expr.expr(role == :member)

  def filter(resource, scope) do
    Enum.find_value(@sources, fn source ->
      if function_exported?(source, :filter, 2), do: source.filter(resource, scope)
    end)
  end
end
