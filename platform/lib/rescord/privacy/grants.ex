defmodule Rescord.Privacy.Grants do
  @moduledoc """
  What a role can do with the privacy of an organisation (ADR 0024 and
  ADR 0105).

  **Each role asks** for the erasure of its own data, from its own page,
  and reads its own requests.

  The power `:privacy` reads each request, records a request that came
  another way, extends, refuses and withdraws one, erases a member or a
  former member, and reads and changes the settings of privacy. Only the
  administrators have it at first. It does not erase a member whose role
  has the power `privacy` or `members`: only a root user does
  (`Rescord.Privacy.erasable?/3`).

  No role has a grant for `complete` and `forget`: the erasure and a job
  run them.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Privacy.{Request, Settings}

  import Ash.Expr, only: [expr: 1, actor: 1]

  @impl true
  def reads, do: [{Request, :ask, :all}, {Request, :read, :own}]

  @impl true
  def powers do
    %{
      privacy:
        for(
          action <- [:read, :open, :record, :extend, :refuse, :withdraw, :note_told],
          do: {Request, action, :all}
        ) ++ [{Settings, :read, :all}, {Settings, :set, :all}, {Settings, :change, :all}]
    }
  end

  @impl true
  def filter(Request, :own), do: expr(user_id == ^actor(:id))
  def filter(_resource, _scope), do: nil
end
