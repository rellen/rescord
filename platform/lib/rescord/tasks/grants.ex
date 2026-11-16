defmodule Rescord.Tasks.Grants do
  @moduledoc """
  What a role can do with the tasks of an organisation (ADR 0024).

  The tasks are the daily work of each member: each member plans a task,
  takes one, gives one to a member, completes one, skips one with a reason,
  and opens one again (`docs/domain.md`, section 4). Each member also starts
  a routine, changes one, and ends one (ADR 0033). An administrator has the
  same grants here.

  No role has a grant for `generate` of a task, or for `generate` and `mark`
  of a routine: Rescord runs those itself.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Tasks.{Routine, Task, TaskSubject}

  @grants [
            {Task, [:read, :plan, :revise, :take, :give, :complete, :skip, :reopen, :cancel]},
            {TaskSubject, [:read]},
            {Routine, [:read, :start, :revise, :pause, :resume, :remove]}
          ]
          |> Enum.flat_map(fn {resource, actions} -> Enum.map(actions, &{resource, &1, :all}) end)

  @impl true
  def grants, do: %{administrator: @grants, member: @grants}
end
