defmodule Rescord.Accounts.Validations.KeepsRoles do
  @moduledoc """
  The role with the key `:administrator` keeps the power `:roles`, so the
  organisation always has a person who can change the roles (ADR 0040).
  """

  use Ash.Resource.Validation

  @impl true
  def validate(%{data: %{key: :administrator}} = changeset, _opts, _context) do
    if :roles in (Ash.Changeset.get_attribute(changeset, :powers) || []),
      do: :ok,
      else:
        {:error, field: :powers, message: "of the administrators keep the change of the roles"}
  end

  def validate(_changeset, _opts, _context), do: :ok
end
