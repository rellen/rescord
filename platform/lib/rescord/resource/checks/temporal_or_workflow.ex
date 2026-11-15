defmodule Rescord.Resource.Checks.TemporalOrWorkflow do
  @moduledoc """
  Refuses to compile a resource that is temporal and has a workflow (ADR 0012).

  A transition of AshStateMachine is not temporal safe, and AshWorkflow builds
  on AshStateMachine. Without this check such a resource compiles, and then
  each transition raises `Ash.Error.Framework.NotTemporalSafe` when it runs.

  It is a transformer and not a verifier, because Spark reports the error of a
  verifier as a warning, and this rule must stop the compile. It changes
  nothing in the resource. It reads the resource as declared, so it also finds
  a `temporal` section that somebody wrote by hand.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @workflow_extensions [AshStateMachine, AshWorkflow]

  @impl true
  def transform(dsl_state) do
    workflow = workflow_extensions(dsl_state)

    if Ash.Resource.Info.temporal?(dsl_state) and workflow != [] do
      {:error,
       Spark.Error.DslError.exception(
         module: Transformer.get_persisted(dsl_state, :module),
         path: [:temporal],
         message: """
         a resource cannot be temporal and have a workflow.

         This resource is temporal and uses #{names(workflow)}, whose changes are not \
         temporal safe: each transition would raise when it runs.

         Give it `temporal?: false`:

             use Rescord.Resource, temporal?: false, ...

         Its history then comes from its paper trail. See ADR 0012.
         """
       )}
    else
      {:ok, dsl_state}
    end
  end

  defp workflow_extensions(dsl_state) do
    extensions = Transformer.get_persisted(dsl_state, :extensions, [])
    Enum.filter(@workflow_extensions, &(&1 in extensions))
  end

  defp names(extensions), do: Enum.map_join(extensions, " and ", &inspect/1)
end
