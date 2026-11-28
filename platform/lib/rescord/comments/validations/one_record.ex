defmodule Rescord.Comments.Validations.OneRecord do
  @moduledoc """
  A comment or a follow names exactly one record. The database holds the
  same rule; this one gives a person words for it.
  """

  use Ash.Resource.Validation

  alias Rescord.Comments.Subject

  @impl true
  def validate(changeset, _opts, _context) do
    named =
      Enum.count(Subject.columns(), &(not is_nil(Ash.Changeset.get_attribute(changeset, &1))))

    if named == 1,
      do: :ok,
      else: {:error, field: :resident_id, message: "name one record"}
  end
end
