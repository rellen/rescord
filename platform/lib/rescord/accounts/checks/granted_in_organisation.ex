defmodule Rescord.Accounts.Checks.GrantedInOrganisation do
  @moduledoc """
  A policy check for an action on an organisation itself: the role of the
  actor in that organisation has a grant for the action.

  An organisation is outside the schemas, so a request for it has no tenant,
  and `Rescord.Accounts.Checks.Granted` cannot find the role. This check
  reads the member of the actor in the organisation that the action changes.
  """

  use Ash.Policy.SimpleCheck

  alias Rescord.Accounts.{Checks.Granted, Grants, Organisation, User}

  @impl true
  def describe(_opts), do: "the role of the actor in the organisation has a grant for the action"

  @impl true
  def match?(
        %User{} = actor,
        %{changeset: %{data: %Organisation{} = organisation, action: action}},
        _opts
      ) do
    role = Granted.role_of(actor, organisation)
    Grants.scope(role, Organisation, action.name) != :none
  end

  def match?(_actor, _context, _opts), do: false
end
