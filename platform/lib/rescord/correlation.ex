defmodule Rescord.Correlation do
  @moduledoc """
  The correlation id that ties together each version that one action writes,
  with the versions of its nested actions and of its listeners (ADR 0100).

  `Rescord.Resource` sets `operation_id_field :correlation_id` of
  AshPaperTrail. When an action starts, AshPaperTrail puts a new id in
  `context.shared.ash_paper_trail.operation_id`, unless one is there, and
  writes it in the column `correlation_id` of each version that the action
  writes. A nested action writes the same id only when it gets the shared
  context of the action that runs it. So:

    * a change that builds the options of a nested action gives it
      `context: Rescord.Correlation.context(changeset)`;
    * a function of a domain that runs two actions or more starts with
      `start/1`, and gives its options to each action.

  A signal listener that runs inline gets the id of the action that emits
  with no help: Ash passes the scope. A job starts a new id.

  ## Examples

      iex> [context: %{shared: %{ash_paper_trail: %{operation_id: id}}}] = Rescord.Correlation.start([])
      iex> Rescord.Correlation.start(context: %{shared: %{ash_paper_trail: %{operation_id: id}}}) ==
      ...>   [context: %{shared: %{ash_paper_trail: %{operation_id: id}}}]
      true
  """

  @doc """
  The context that a change gives a nested action: the ids of the action
  that runs it, so that the versions of both have the same correlation id
  and the nested one names its cause. It holds nothing else of the shared
  context: an instant of `as_of` that the nested action should use, a
  change passes as an option, as it did before.

      options = [
        actor: context.actor,
        tenant: changeset.tenant,
        context: Rescord.Correlation.context(changeset),
        authorize?: false
      ]
  """
  @spec context(Ash.Changeset.t()) :: map
  def context(%Ash.Changeset{context: context}) do
    case Map.take(context[:shared] || %{}, [:ash_paper_trail, :rescord]) do
      ids when map_size(ids) == 0 -> %{}
      ids -> %{shared: ids}
    end
  end

  @doc """
  The options `opts` with a correlation id: the one that they hold, or a new
  one. A function of a domain that runs several actions calls it first and
  gives the result to each action, so that they write one id.
  """
  @spec start(keyword) :: keyword
  def start(opts) when is_list(opts) do
    context = Keyword.get(opts, :context, %{})

    case get_in(context, [:shared, :ash_paper_trail, :operation_id]) do
      nil -> Keyword.put(opts, :context, put_id(context, Ash.UUIDv7.generate()))
      _id -> opts
    end
  end

  defp put_id(context, id) do
    shared = Map.get(context, :shared, %{})
    trail = shared |> Map.get(:ash_paper_trail, %{}) |> Map.put(:operation_id, id)
    Map.put(context, :shared, Map.put(shared, :ash_paper_trail, trail))
  end
end
