defmodule Rescord.Comments.Validations.SubjectReadable do
  @moduledoc """
  The actor can read the record that a comment or a follow names, in the
  organisation of the request. It reads as the actor, so it runs after the
  policy (`before_action?: true`): a person with no grant gets the answer of
  the policy.
  """

  use Ash.Resource.Validation

  alias Rescord.Comments.Subject

  @impl true
  def validate(changeset, _opts, context) do
    subject =
      Enum.find_value(Subject.kinds(), fn kind ->
        case Ash.Changeset.get_attribute(changeset, Subject.column(kind)) do
          nil -> nil
          id -> {kind, id}
        end
      end)

    if subject && Subject.readable?(subject, actor: context.actor, tenant: changeset.tenant),
      do: :ok,
      else: {:error, field: :resident_id, message: "is not a record that you can read"}
  end
end
