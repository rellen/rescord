defmodule Rescord.Reports do
  @moduledoc """
  The reports of an organisation: documents for paper, each a PDF that Typst
  writes through AshTypst (ADR 0076).

  A report is a generic action of `Rescord.Reports.Report`, and each function
  here returns `{:ok, %AshTypst.Document{}}` with the bytes of the PDF in
  `data`:

      Rescord.Reports.resident_record(resident.id, actor: user, tenant: organisation)
      Rescord.Reports.register(%{on: ~D[2026-11-28]}, actor: user, tenant: organisation)

  A report reads as the person who asks, in the organisation of the request,
  so it holds what that person reads on the pages and nothing else. Each
  role can make each report: `Rescord.Reports.Grants`.

  `Rescord.Reports.Render` says how the facts become a document.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary]

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true

    deps [
      Rescord,
      Rescord.Accounts,
      Rescord.Lists,
      Rescord.Residents,
      Rescord.Locations,
      Rescord.Journal,
      Rescord.Photos,
      Rescord.Tasks,
      Rescord.Inventory
    ]

    # The web layer words the facts (`Rescord.Reports.Wording`).
    exports [Rescord.Reports.Wording]
  end

  resources do
    resource Rescord.Reports.Report do
      define :resident_record, action: :resident_record, args: [:resident_id]
      define :cage_card, action: :cage_card, args: [:resident_id]
      define :register, action: :register
      define :movements, action: :movements, args: [:from, :to]
      define :task_sheet, action: :task_sheet
      define :stock, action: :stock
      define :housing, action: :housing
    end
  end

  @reports [:resident_record, :cage_card, :register, :movements, :task_sheet, :stock, :housing]

  @doc "The reports, each by the name of its action."
  @spec reports() :: [atom]
  def reports, do: @reports

  @typedoc """
  Why a report was not made: the person made too many, the person may not
  make it, a record that it names is not there, an argument is not right
  (with the argument and words that follow its name, such as "is after
  today"), or a fault of Rescord.
  """
  @type reason :: :too_many | :forbidden | :not_found | {:invalid, atom, String.t()} | :fault

  @doc """
  Why a report was not made, from the error of its function. A page reads
  the reason, so that it needs no module of Ash.
  """
  @spec reason(term) :: reason
  def reason(%Ash.Error.Forbidden{errors: errors}) do
    if Enum.any?(errors, &is_struct(&1, AshRateLimiter.LimitExceeded)),
      do: :too_many,
      else: :forbidden
  end

  def reason(%Ash.Error.Invalid{errors: errors}) do
    cond do
      Enum.any?(errors, &is_struct(&1, Ash.Error.Query.NotFound)) ->
        :not_found

      argument = Enum.find(errors, &is_struct(&1, Ash.Error.Action.InvalidArgument)) ->
        {:invalid, argument.field, argument.message}

      true ->
        :fault
    end
  end

  def reason(_error), do: :fault
end
