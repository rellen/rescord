defmodule Rescord.Accounts.Signals do
  @moduledoc """
  What the accounts tell their listeners (ADR 0067).

    * `:member_invited` - a person was invited to an organisation: the
      organisation of the action that emitted. `Rescord.Accounts.Member`
      listens in a job, which sends the email of the invitation after the
      commit, and again after a fault.

  `mix ash.signals` prints what emits each signal and what listens to it.
  """

  use Ash.Signals

  signals do
    signal :member_invited do
      description "A person was invited to the organisation of the action"
      argument :email, :ci_string, allow_nil?: false
      argument :invited_by, :ci_string
    end
  end
end
