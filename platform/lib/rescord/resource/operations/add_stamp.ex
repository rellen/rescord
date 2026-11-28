defmodule Rescord.Resource.Operations.AddStamp do
  @moduledoc """
  Puts `Rescord.Resource.Operations.Stamp` first in each create, update and
  destroy action. A global change would run after the changes of the
  action, so each action gets the change of its own.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:actions])
    |> Enum.filter(&(&1.type in [:create, :update, :destroy]))
    |> Enum.reduce_while({:ok, dsl_state}, fn action, {:ok, dsl_state} ->
      case Transformer.build_entity(Ash.Resource.Dsl, [:actions, action.type], :change,
             change: Rescord.Resource.Operations.Stamp
           ) do
        {:ok, change} ->
          action = %{action | changes: [change | action.changes]}

          {:cont,
           {:ok,
            Transformer.replace_entity(
              dsl_state,
              [:actions],
              action,
              &(&1.name == action.name and &1.type == action.type)
            )}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  # The default actions and the expanded pipelines must be there first.
  @impl true
  def after?(Ash.Resource.Transformers.SetPrimaryActions), do: true
  def after?(Ash.Resource.Transformers.ResolvePipelines), do: true
  def after?(_transformer), do: false
end
