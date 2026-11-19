defmodule Rescord.Accounts.Validations.KnownPowers do
  @moduledoc "Each power of a role is a power that Rescord knows."

  use Ash.Resource.Validation

  alias Rescord.Accounts.Grants

  @impl true
  def validate(changeset, _opts, _context) do
    powers = Ash.Changeset.get_attribute(changeset, :powers) || []

    if Enum.all?(powers, &(&1 in Grants.power_keys())),
      do: :ok,
      else: {:error, field: :powers, message: "has a power that Rescord does not know"}
  end
end
