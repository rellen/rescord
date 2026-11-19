defmodule Rescord.Accounts.Changes.SetRole do
  @moduledoc """
  Gives a member its role (ADR 0040): the role that the argument `role_id`
  names, or else the role of the organisation with the key of the option
  `key`.

  The change only sets the id. `Rescord.Accounts.Validations.WithinPowers`
  refuses an id that names no role of the organisation, and a role with a
  power that the role of the person does not have.

  ## Options

    * `key` - `:administrator`, `:member`, or `nil` when the argument
      `role_id` is necessary.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Accounts.Role

  @impl true
  def change(changeset, opts, _context) do
    role_id =
      case Ash.Changeset.fetch_argument(changeset, :role_id) do
        {:ok, id} when is_binary(id) -> id
        _none -> role_with_key(opts[:key], changeset.tenant)
      end

    if role_id,
      do: Ash.Changeset.force_change_attribute(changeset, :role_id, role_id),
      else: Ash.Changeset.add_error(changeset, field: :role_id, message: "is required")
  end

  defp role_with_key(nil, _tenant), do: nil

  defp role_with_key(key, tenant) do
    Role
    |> Ash.Query.filter(key == ^key)
    |> Ash.Query.select([:id])
    |> Ash.read_one!(tenant: tenant, authorize?: false)
    |> case do
      nil -> nil
      role -> role.id
    end
  end
end
