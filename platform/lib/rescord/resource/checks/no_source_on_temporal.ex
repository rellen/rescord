defmodule Rescord.Resource.Checks.NoSourceOnTemporal do
  @moduledoc """
  Refuses to compile a temporal resource with a paper trail that gives an
  attribute a column of another name (ADR 0027).

  The version resource of such a resource reads the same table. AshPaperTrail
  0.8.1 copies each attribute to it without its `source`, so the version
  resource asks for a column with the name of the attribute. Without this
  check the resource compiles and works, and a read of its versions fails
  with `undefined_column`.

  It is a transformer and not a verifier, for the reason that
  `Rescord.Resource.Checks.TemporalOrWorkflow` gives.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  # The attributes must be there in full, with the ones of the extensions.
  @impl true
  def after?(_transformer), do: true

  @impl true
  def transform(dsl_state) do
    renamed =
      if Ash.Resource.Info.temporal?(dsl_state) and
           AshPaperTrail.Resource in Transformer.get_persisted(dsl_state, :extensions, []) do
        dsl_state
        |> Ash.Resource.Info.attributes()
        |> Enum.filter(&(not is_nil(&1.source) and &1.source != &1.name))
      else
        []
      end

    case renamed do
      [] ->
        {:ok, dsl_state}

      attributes ->
        {:error,
         Spark.Error.DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           path: [:attributes],
           message: """
           a temporal resource with a paper trail cannot give an attribute a column of \
           another name.

           #{Enum.map_join(attributes, ", ", &"#{inspect(&1.name)} has `source #{inspect(&1.source)}`")}. \
           The version resource reads the column by the name of the attribute, so a read of \
           the versions would fail.

           Give the attribute the name of its column, for example `:retired` and not \
           `:retired?`. See ADR 0027.
           """
         )}
    end
  end
end
