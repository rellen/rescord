defmodule Rescord.Tasks.Grants do
  @moduledoc """
  What a role can do with the tasks of an organisation (ADR 0024).

  Each role reads the tasks and the routines. The power `:tasks` is the
  daily work of each member: it plans a task, takes one, gives one to
  members, completes one, skips one with a reason, and opens one again
  (`docs/domain.md`, section 4).

  The power `:routines` starts a routine, changes one, stops one for a time,
  and ends one. Only the administrators have it at first (the maintainer,
  18 November 2026, ADR 0039 and ADR 0040).

  No role has a grant for `generate` of a task, or for `generate` and `mark`
  of a routine: Rescord runs those itself.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Tasks.{Routine, Task, TaskSubject}

  @impl true
  def reads, do: for(resource <- [Task, TaskSubject, Routine], do: {resource, :read, :all})

  @impl true
  def powers do
    %{
      tasks:
        for(
          action <- [:plan, :revise, :take, :give, :complete, :skip, :reopen, :cancel],
          do: {Task, action, :all}
        ),
      routines:
        for(action <- [:start, :revise, :pause, :resume, :remove], do: {Routine, action, :all})
    }
  end
end
