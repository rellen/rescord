defmodule Rescord.Accounts.Validations.WithinPowers do
  @moduledoc """
  A person gives only the powers that their own role has (ADR 0040): to a
  role that they define or change, and to a member, through the role that
  they give them. So no person can give themselves, or another person, a
  power that they do not have. A root user is outside this rule.

  The powers are those of the attribute `powers` of a role, or those of the
  role that `role_id` of a member names. A `role_id` that names no role of
  the organisation is refused, for a root user too. The validation runs
  after the policy, so a person with no grant gets the answer of the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Accounts.{Checks.Granted, Role, User}

  @impl true
  def validate(changeset, _opts, context) do
    case given(changeset) do
      :no_role ->
        {:error, field: :role_id, message: "is not a role of this organisation"}

      powers ->
        if within?(powers, context.actor, changeset.tenant),
          do: :ok,
          else:
            {:error,
             field: field(changeset), message: "gives a power that your role does not have"}
    end
  end

  defp within?(_powers, %User{root?: true}, _tenant), do: true

  defp within?(powers, %User{} = actor, tenant) do
    own =
      case Granted.role_of(actor, tenant) do
        %Role{powers: own} -> own
        _no_role -> []
      end

    Enum.all?(powers, &(&1 in own))
  end

  # With no user, the policy refuses the action.
  defp within?(_powers, _actor, _tenant), do: true

  defp field(%{resource: Role}), do: :powers
  defp field(_member), do: :role_id

  defp given(%{resource: Role} = changeset),
    do: Ash.Changeset.get_attribute(changeset, :powers) || []

  defp given(changeset) do
    case Ash.Changeset.get_attribute(changeset, :role_id) do
      nil ->
        []

      role_id ->
        Role
        |> Ash.Query.filter(id == ^role_id)
        |> Ash.read_one(tenant: changeset.tenant, authorize?: false)
        |> case do
          {:ok, %Role{powers: powers}} -> powers
          _no_role -> :no_role
        end
    end
  end
end
