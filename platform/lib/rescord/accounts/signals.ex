defmodule Rescord.Accounts.Signals do
  @moduledoc """
  What the accounts tell their listeners (ADR 0067).

    * `:member_invited` - a person was invited to an organisation: the
      organisation of the action that emitted. `Rescord.Accounts.Member`
      listens in a job, which sends the email of the invitation after the
      commit, and again after a fault.

    * `:member_removed` - a member was taken out of the organisation: the
      organisation of the action that emitted. The tasks and the routines
      that are open let go of the user, and the calendar feeds of the member
      are revoked (ADR 0105).

  `mix ash.signals` prints what emits each signal and what listens to it.
  """

  use Ash.Signals

  signals do
    signal :member_invited do
      description "A person was invited to the organisation of the action"
      argument :email, :ci_string, allow_nil?: false
      argument :invited_by, :ci_string
    end

    signal :member_removed do
      description "A member was taken out of the organisation of the action"
      argument :user_id, :uuid, allow_nil?: false
    end
  end
end
