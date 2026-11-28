defmodule Rescord.Tasks.Errors.NoPrescription do
  @moduledoc """
  A task that names a prescription was completed, and the prescription is
  not there for the member, so the dose has no entry in the journal
  (ADR 0077, E2). The completion stops: a task is not done with no record of
  the dose.
  """

  use Splode.Error, fields: [], class: :invalid

  @impl true
  def message(_error), do: "The prescription of the task is not there"
end
