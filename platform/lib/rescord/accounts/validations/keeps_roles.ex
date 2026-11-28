defmodule Rescord.Accounts.Validations.KeepsRoles do
  @moduledoc """
  The role with the key `:administrator` keeps the power `:roles`, so the
  organisation always has a person who can change the roles (ADR 0040),
  and the power `:members`, so that it has a person who can change the
  members (issue 38, F3). Without the second, an administrator could take
  `:members` from the role, and then could not give it back.
  """

  use Ash.Resource.Validation

  @kept [:roles, :members]

  @impl true
  def validate(%{data: %{key: :administrator}} = changeset, _opts, _context) do
    powers = Ash.Changeset.get_attribute(changeset, :powers) || []

    if Enum.all?(@kept, &(&1 in powers)),
      do: :ok,
      else:
        {:error,
         field: :powers,
         message: "of the administrators keep the change of the roles and of the members"}
  end

  def validate(_changeset, _opts, _context), do: :ok
end
