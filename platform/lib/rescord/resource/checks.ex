defmodule Rescord.Resource.Checks do
  @moduledoc """
  The checks that each resource of Rescord passes when it compiles.

  `use Rescord.Resource` adds this extension. It has no DSL of its own. Each
  check is a transformer that changes nothing and stops the compile when its
  rule is broken.
  """

  use Spark.Dsl.Extension,
    transformers: [Rescord.Resource.Checks.TemporalOrWorkflow]
end
