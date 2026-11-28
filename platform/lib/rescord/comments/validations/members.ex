defmodule Rescord.Comments.Validations.Members do
  @moduledoc """
  Each person told is a member of the organisation, and nobody is told
  twice. The writer is not told: they follow the record already.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Accounts.Member

  @impl true
  def validate(changeset, _opts, context) do
    told = Ash.Changeset.get_attribute(changeset, :told_ids) || []

    cond do
      told == [] ->
        :ok

      length(told) > 50 ->
        {:error, field: :told_ids, message: "tell 50 people at most"}

      true ->
        members =
          Member
          |> Ash.Query.filter(user_id in ^told)
          |> Ash.read!(tenant: changeset.tenant, actor: context.actor)
          |> MapSet.new(& &1.user_id)

        if Enum.all?(told, &MapSet.member?(members, &1)),
          do: :ok,
          else: {:error, field: :told_ids, message: "tell only the members of the organisation"}
    end
  end
end
