defmodule Rescord.Journal.Grants do
  @moduledoc """
  What a role can do with the journal of a resident (ADR 0024).

  Each role reads the journal and its files. The power `:journal` writes an
  entry, attaches a file, and corrects the entries and removes the files
  that the person wrote: the scope `own`. It also marks a condition of a
  resident as resolved, opens it again and revises it (ADR 0083). The power
  `:correct_journal` corrects each entry, removes each file, and removes a
  condition that was recorded by mistake (`docs/domain.md`, section 5.6, and
  ADR 0040). A member has the first at first, and an administrator both. A role reads the facts of an entry,
  and writes them only through the entry.
  """

  @behaviour Rescord.Accounts.Grants

  import Ash.Expr, only: [expr: 1, actor: 1]

  alias Rescord.Journal.{
    Attachment,
    Diagnosis,
    Dose,
    Episode,
    JournalEntry,
    Measurement,
    Prescription,
    Procedure,
    Vaccination
  }

  @impl true
  def reads do
    for resource <- [
          JournalEntry,
          Diagnosis,
          Measurement,
          Procedure,
          Vaccination,
          Prescription,
          Dose,
          # A file of an entry (ADR 0041).
          Attachment,
          # A condition of a resident (ADR 0083).
          Episode
        ],
        do: {resource, :read, :all}
  end

  @impl true
  def powers do
    %{
      journal: [
        {JournalEntry, :write, :all},
        {JournalEntry, :correct, :own},
        {Attachment, :attach, :all},
        {Attachment, :remove, :own},
        # The conditions of a resident (ADR 0083). A diagnosis starts one.
        {JournalEntry, :track, :all},
        {Episode, :resolve, :all},
        {Episode, :reopen, :all},
        {Episode, :revise, :all}
      ],
      correct_journal: [
        {JournalEntry, :correct, :all},
        {Attachment, :remove, :all},
        {Episode, :remove, :all}
      ]
    }
  end

  @impl true
  def filter(JournalEntry, :own), do: expr(author_id == ^actor(:id))
  def filter(Attachment, :own), do: expr(author_id == ^actor(:id))
  def filter(_resource, _scope), do: nil
end
