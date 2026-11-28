defmodule Rescord.Reports.Grants do
  @moduledoc """
  Who can make a report (ADR 0024 and ADR 0076).

  Each report is a read: each role makes each one. A report holds what the
  person reads on the pages, and each record in it passes the policy of its
  own resource as that person, so a report gives a role nothing new. There
  is no power here.
  """

  @behaviour Rescord.Accounts.Grants

  @impl true
  def reads,
    do: for(report <- Rescord.Reports.reports(), do: {Rescord.Reports.Report, report, :all})

  @impl true
  def powers, do: %{}
end
