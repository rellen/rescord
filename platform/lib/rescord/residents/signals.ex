defmodule Rescord.Residents.Signals do
  @moduledoc """
  What the residents tell the other domains (ADR 0067).

  The domains that depend on the residents listen with an action of their
  own (`signals_in`). `Rescord.Residents` does not know them: it uses none
  of them.

    * `:resident_removed` - an administrator removed a resident that was
      recorded by mistake. The listeners run in the transaction of the
      removal and as of its instant, so a fault in one of them undoes the
      removal.
    * `:resident_departed` - a member recorded that a resident left: a
      death, a release or a transfer. The listeners run in the transaction
      of the departure. A departure that a member withdraws later sends no
      signal, and restores nothing.

  `mix ash.signals` prints what emits each signal and what listens to it.
  """

  use Ash.Signals

  signals do
    signal :resident_removed do
      description "An administrator removed a resident that was recorded by mistake"
      argument :resident_id, :uuid, allow_nil?: false
    end

    signal :resident_departed do
      description "A member recorded that a resident left the organisation"
      argument :resident_id, :uuid, allow_nil?: false
    end
  end
end
