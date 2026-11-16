defmodule Rescord.Journal.Grants do
  @moduledoc """
  What a role can do with the journal of a resident (ADR 0024).

  Each member reads the journal and writes an entry. A member corrects the
  entries that they wrote: the scope `own`. An administrator corrects each
  entry (`docs/domain.md`, section 5.6). A role reads the facts of an entry,
  and writes them only through the entry.
  """

  @behaviour Rescord.Accounts.Grants

  import Ash.Expr, only: [expr: 1, actor: 1]

  alias Rescord.Journal.{
    Diagnosis,
    Dose,
    JournalEntry,
    Measurement,
    Prescription,
    Procedure,
    Vaccination
  }

  @reads for resource <- [
               JournalEntry,
               Diagnosis,
               Measurement,
               Procedure,
               Vaccination,
               Prescription,
               Dose
             ],
             do: {resource, :read, :all}

  @impl true
  def grants do
    %{
      administrator: @reads ++ [{JournalEntry, :write, :all}, {JournalEntry, :correct, :all}],
      member: @reads ++ [{JournalEntry, :write, :all}, {JournalEntry, :correct, :own}]
    }
  end

  @impl true
  def filter(JournalEntry, :own), do: expr(author_id == ^actor(:id))
  def filter(_resource, _scope), do: nil
end
