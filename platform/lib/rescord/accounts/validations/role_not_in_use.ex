defmodule Rescord.Accounts.Validations.RoleNotInUse do
  @moduledoc """
  A role that goes is a role that the organisation defined, and that no
  member has. Each organisation keeps its two roles with a key. The
  validation runs after the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Accounts.Member

  @impl true
  def validate(%{data: %{key: key}}, _opts, _context) when not is_nil(key),
    do: {:error, field: :name, message: "is a role that each organisation has"}

  def validate(%{data: role} = changeset, _opts, _context) do
    in_use? =
      Member
      |> Ash.Query.filter(role_id == ^role.id)
      |> Ash.exists?(tenant: changeset.tenant, authorize?: false)

    if in_use?,
      do:
        {:error,
         field: :name, message: "is the role of a member: give the member another role first"},
      else: :ok
  end
end
