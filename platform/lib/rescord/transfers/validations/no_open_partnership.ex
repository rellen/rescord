defmodule Rescord.Transfers.Validations.NoOpenPartnership do
  @moduledoc """
  Two refuges have one partnership that is asked or accepted at a time, in
  either direction. The validation runs after the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Transfers.Partnership

  @impl true
  def validate(changeset, _opts, _context) do
    a = Ash.Changeset.get_attribute(changeset, :from_organisation_id)
    b = Ash.Changeset.get_attribute(changeset, :to_organisation_id)

    open? =
      Partnership
      |> Ash.Query.filter(
        state in [:asked, :accepted] and
          ((from_organisation_id == ^a and to_organisation_id == ^b) or
             (from_organisation_id == ^b and to_organisation_id == ^a))
      )
      |> Ash.exists?(authorize?: false)

    if open?,
      do:
        {:error,
         field: :short_name,
         message: "names a refuge that is a partner, or that has a question open"},
      else: :ok
  end
end
