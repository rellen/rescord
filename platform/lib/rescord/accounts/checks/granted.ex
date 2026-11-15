defmodule Rescord.Accounts.Checks.Granted do
  @moduledoc """
  A policy check: the role of the actor in the organisation has a grant for
  the action, and the record is in the scope of the grant.

  The check reads the member of the actor in the tenant of the request. An
  actor who is not a member there has no role, and thus no grant. The check
  gives a filter, so a read returns only the records of the scope, and a
  write is refused for a record outside it.
  """

  use Ash.Policy.FilterCheck

  require Ash.Query

  alias Rescord.Accounts.{Grants, Member, User}

  @impl true
  def describe(_opts), do: "the role of the actor in the organisation has a grant for the action"

  @impl true
  def filter(%User{} = actor, %{resource: resource, action: action, subject: subject}, _opts) do
    with tenant when not is_nil(tenant) <- subject.tenant,
         role when not is_nil(role) <- role_of(actor, tenant),
         {:ok, scope} <- Grants.scope(role, resource, action.name) do
      Grants.filter(resource, scope)
    else
      _no_grant -> false
    end
  end

  def filter(_actor, _authorizer, _opts), do: false

  @doc "The role of a user in an organisation, or `nil` for a user who is not a member."
  def role_of(%User{id: user_id}, tenant) do
    Member
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.select([:role])
    |> Ash.read_one!(tenant: tenant, authorize?: false)
    |> case do
      nil -> nil
      member -> member.role
    end
  end
end
