defmodule Rescord.Resource.Operations do
  @moduledoc """
  Stamps each create, update and destroy of a resource with a paper trail
  with the operation id of its call and the causation id of the call that
  ran it (ADR 0101).

  `use Rescord.Resource` adds this extension to each resource with a paper
  trail. It has no DSL of its own: its transformer puts the change
  `Rescord.Resource.Operations.Stamp` first in each such action, so that the
  ids are in the context before any other change, and before AshPaperTrail
  writes the version.
  """

  use Spark.Dsl.Extension, transformers: [Rescord.Resource.Operations.AddStamp]
end
