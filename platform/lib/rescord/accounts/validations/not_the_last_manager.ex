defmodule Rescord.Accounts.Validations.NotTheLastManager do
  @moduledoc """
  Refuses to remove the last member whose role has the power `:members`
  (ADR 0105).

  Without such a member nobody in the organisation can invite a person,
  change a role or remove a member, and only a root user could put it right.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Accounts.{Member, Role}

  @impl true
  def validate(changeset, _opts, _context) do
    member = changeset.data
    managers = managers(changeset.tenant)

    cond do
      member.role_id not in managers ->
        :ok

      other_manager?(member, managers, changeset.tenant) ->
        :ok

      true ->
        {:error,
         field: :role_id, message: "is the last member who can change the members, and stays one"}
    end
  end

  defp other_manager?(member, managers, tenant) do
    Member
    |> Ash.Query.filter(id != ^member.id and role_id in ^managers and is_nil(archived_at))
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end

  defp managers(tenant) do
    Role
    |> Ash.Query.select([:id, :powers])
    |> Ash.read!(tenant: tenant, authorize?: false)
    |> Enum.filter(&(:members in &1.powers))
    |> Enum.map(& &1.id)
  end
end
