defmodule Rescord.Reports.Report do
  @moduledoc """
  The reports of an organisation, each as a generic action that returns a
  PDF in an `AshTypst.Document` (ADR 0076).

  The resource has no table. Its section `typst` holds the templates, which
  are the files of `priv/typst`: AshTypst checks the syntax of each one when
  this module compiles. The fonts are the ones of `priv/typst/fonts`, and a
  render ignores the fonts of the server, so each server writes the same
  document.

  An action is not a `render` of AshTypst, which gives a template the
  records of one read. A report reads several domains and carries photos,
  so `Rescord.Reports.Render` runs each action: it reads the facts as the
  person, has them worded, and renders the template.

  A request names its organisation as the tenant, and the policy is the
  usual one: `Rescord.Reports.Grants` gives each report to each role. A
  person makes at most 30 reports in a minute, in one count for all the
  reports (ADR 0020).

  Each action takes `paper`, A4 or US Letter (ADR 0093). With none, the
  document is on the paper of the organisation.
  """

  use Rescord.Resource,
    domain: Rescord.Reports,
    table?: false,
    extensions: [AshTypst.Resource, AshRateLimiter],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Reports.Render

  # The papers of a document, and what the argument `paper` says (ADR 0093).
  @papers Rescord.Accounts.paper_sizes()
  @paper "The paper of the document, or none for the paper of the organisation"

  typst do
    root({:rescord, "priv/typst"})
    font_paths([{:rescord, "priv/typst/fonts"}])
    ignore_system_fonts(true)

    template :resident_record do
      source "resident_record.typ"
    end

    template :cage_card do
      source "cage_card.typ"
    end

    template :register do
      source "register.typ"
    end

    template :movements do
      source "movements.typ"
    end

    template :task_sheet do
      source "task_sheet.typ"
    end

    template :stock do
      source "stock.typ"
    end

    template :housing do
      source "housing.typ"
    end

    template :expenses do
      source "expenses.typ"
    end
  end

  rate_limit do
    backend Rescord.RateLimit

    action :resident_record, limit: 30, per: :timer.minutes(1), key: &__MODULE__.person_key/2
    action :cage_card, limit: 30, per: :timer.minutes(1), key: &__MODULE__.person_key/2
    action :register, limit: 30, per: :timer.minutes(1), key: &__MODULE__.person_key/2
    action :movements, limit: 30, per: :timer.minutes(1), key: &__MODULE__.person_key/2
    action :task_sheet, limit: 30, per: :timer.minutes(1), key: &__MODULE__.person_key/2
    action :stock, limit: 30, per: :timer.minutes(1), key: &__MODULE__.person_key/2
    action :housing, limit: 30, per: :timer.minutes(1), key: &__MODULE__.person_key/2
    action :expenses, limit: 30, per: :timer.minutes(1), key: &__MODULE__.person_key/2
  end

  actions do
    action :resident_record, AshTypst.Type.Document do
      description "The record of one resident: its facts, its stay, its medical history, and its photos on request"

      argument :resident_id, :uuid, allow_nil?: false

      argument :journal, :atom do
        description "The part of the journal in the record: the medical history, all of it, or none"
        constraints one_of: [:medical, :all, :none]
        default :medical
        allow_nil? false
      end

      argument :photos, :boolean do
        description "Whether the record holds the photos of the resident"
        default false
        allow_nil? false
      end

      argument :paper, :atom, constraints: [one_of: @papers], description: @paper
      run {Render, report: :resident_record}
    end

    action :cage_card, AshTypst.Type.Document do
      description "One page about a resident for the door of its pen"
      argument :resident_id, :uuid, allow_nil?: false
      argument :paper, :atom, constraints: [one_of: @papers], description: @paper
      run {Render, report: :cage_card}
    end

    action :register, AshTypst.Type.Document do
      description "Each resident that the organisation had at the end of a day, today when no day is given"
      argument :on, :date
      argument :paper, :atom, constraints: [one_of: @papers], description: @paper
      run {Render, report: :register}
    end

    action :movements, AshTypst.Type.Document do
      description "The arrivals and the departures of a period, with their totals"
      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false
      argument :paper, :atom, constraints: [one_of: @papers], description: @paper
      run {Render, report: :movements}
    end

    action :task_sheet, AshTypst.Type.Document do
      description "The tasks that are due on one day, today when no day is given, each with a box to tick"
      argument :on, :date
      argument :paper, :atom, constraints: [one_of: @papers], description: @paper
      run {Render, report: :task_sheet}
    end

    action :stock, AshTypst.Type.Document do
      description "The stock of each item, and what needs somebody first"
      argument :paper, :atom, constraints: [one_of: @papers], description: @paper
      run {Render, report: :stock}
    end

    action :housing, AshTypst.Type.Document do
      description "The locations of the organisation, each with who lives there"
      argument :paper, :atom, constraints: [one_of: @papers], description: @paper
      run {Render, report: :housing}
    end

    action :expenses, AshTypst.Type.Document do
      description "The expenses of a period that the person reads, with their sums, and what the organisation owes to each member"

      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false
      argument :paper, :atom, constraints: [one_of: @papers], description: @paper
      run {Render, report: :expenses}
    end
  end

  policies do
    # A root user can do anything.
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy always() do
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  @doc "The key of the count of the reports of one person, for the rate limit."
  def person_key(_input, %{actor: %{id: id}}) when is_binary(id), do: "reports/person/" <> id
  def person_key(_input, _context), do: "reports/nobody"
end
