defmodule Rescord.Resource.VersionTable do
  @moduledoc """
  What `Rescord.Resource` mixes into the version resource of a resource that
  is not temporal, which has a table of its own: the policies of
  `Rescord.Resource.VersionPolicies`, and the index of the correlation id
  (ADR 0101). The version rows from before ADR 0101 have no id, so the
  index holds only the rows that have one.
  """

  defmacro __using__(_opts) do
    quote do
      use Rescord.Resource.VersionPolicies

      postgres do
        custom_indexes do
          index [:correlation_id], where: "correlation_id IS NOT NULL"
        end
      end
    end
  end
end
