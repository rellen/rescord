defmodule Rescord.Privacy.Validations.FitsExtension do
  @moduledoc """
  An extension of a request is at most two months after the day that it
  was due, and the person was told inside the first month (ADR 0105, GDPR
  Article 12(3)).
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    due = changeset.data.due_on
    to = Ash.Changeset.get_attribute(changeset, :extended_to)
    told = Ash.Changeset.get_attribute(changeset, :told_of_extension_on)

    cond do
      is_nil(to) or is_nil(told) ->
        :ok

      Date.compare(to, due) != :gt ->
        {:error, field: :extended_to, message: "is not after the day that the request is due"}

      Date.compare(to, Date.shift(due, month: 2)) == :gt ->
        {:error,
         field: :extended_to, message: "is more than two months after the day that it was due"}

      Date.compare(told, due) == :gt ->
        {:error, field: :told_of_extension_on, message: "is after the first month"}

      true ->
        :ok
    end
  end
end
