defmodule Rescord.Accounts.Grants do
  @moduledoc """
  What a role can do (`docs/architecture.md`, "Policies and roles").

  A grant names a resource, an action and a scope. A scope is a named filter
  on the resource: a role can run the action on the records that the scope
  holds. A role appears in no policy. The policy of a resource is the check
  `Rescord.Accounts.Checks.Granted`, which reads the grants of the role of
  the actor in the organisation.

  A root user is outside the grants: a root user can do anything.

  The roles and their grants are in this module for now. When an organisation
  needs roles of its own, they move to the database (ADR 0021).
  """

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
      {Member, :remove, :members}
    ],
    member: [
      {Member, :read, :all}
    ]
  }

  @doc "The roles that have grants."
  @spec roles() :: [role]
  def roles, do: Map.keys(@grants)

  @doc "The grants of a role, each as `{resource, action, scope}`."
  @spec grants(role) :: [{module, atom, scope}]
  def grants(role), do: Map.get(@grants, role, [])

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
end
