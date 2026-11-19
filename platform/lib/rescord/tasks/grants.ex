defmodule Rescord.Tasks.Grants do
  @moduledoc """
  What a role can do with the tasks of an organisation (ADR 0024).

  The tasks are the daily work of each member: each member plans a task,
  takes one, gives one to members, completes one, skips one with a reason,
  and opens one again (`docs/domain.md`, section 4). An administrator has the
  same grants for the tasks.

  Only an administrator starts a routine, changes one, stops one for a
  time, and ends one (the maintainer, 18 November 2026, ADR 0039). A member
  reads the routines.

  No role has a grant for `generate` of a task, or for `generate` and `mark`
  of a routine: Rescord runs those itself.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Tasks.{Routine, Task, TaskSubject}

  @member [
            {Task, [:read, :plan, :revise, :take, :give, :complete, :skip, :reopen, :cancel]},
            {TaskSubject, [:read]},
            {Routine, [:read]}
          ]
          |> Enum.flat_map(fn {resource, actions} -> Enum.map(actions, &{resource, &1, :all}) end)

  @administrator @member ++
                   Enum.map([:start, :revise, :pause, :resume, :remove], &{Routine, &1, :all})

  @impl true
  def grants, do: %{administrator: @administrator, member: @member}
end
