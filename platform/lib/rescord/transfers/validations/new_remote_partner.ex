defmodule Rescord.Transfers.Validations.NewRemotePartner do
  @moduledoc """
  A refuge records a partner on another server one time while the
  partnership lasts, and never its own card. The validation runs after the
  policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Transfers.RemotePartner

  @impl true
  def validate(changeset, _opts, _context) do
    organisation_id = Ash.Changeset.get_attribute(changeset, :organisation_id)
    refuge_id = Ash.Changeset.get_attribute(changeset, :refuge_id)

    cond do
      refuge_id == organisation_id ->
        {:error, field: :card, message: "is the card of this refuge"}

      RemotePartner
      |> Ash.Query.filter(
        organisation_id == ^organisation_id and refuge_id == ^refuge_id and state == :active
      )
      |> Ash.exists?(authorize?: false) ->
        {:error, field: :card, message: "is the card of a partner that this refuge recorded"}

      true ->
        :ok
    end
  end
end
