defmodule Rescord.Resource.VersionPolicies do
  @moduledoc """
  The policies of each version resource (ADR 0063): no actor passes them.

  AshPaperTrail makes a version resource for each resource with a paper
  trail, and it gives that resource no authorizer. A read of the versions
  with an actor would then return the history of each record to any actor,
  and to no actor at all. `Rescord.Resource` mixes this module into each
  version resource, with the authorizer of the policies, so such a read is
  forbidden.

  A domain reads the versions itself, with `authorize?: false`, after the
  record that they belong to has passed its own policy: see
  `Rescord.Residents.changes/2`. AshPaperTrail writes a version with no
  authorization, so these policies do not stop the trail.
  """

  defmacro __using__(_opts) do
    quote do
      policies do
        policy always() do
          forbid_if always()
        end
      end
    end
  end
end
