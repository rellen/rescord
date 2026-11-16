defmodule Rescord.Journal.EntryKind do
  @moduledoc """
  The kind of a journal entry (`docs/domain.md`, section 5.6). A fixed list
  (ADR 0025). The first seven kinds are the medical history of a resident.
  """

  use Ash.Type.Enum,
    values: [
      :examination,
      :diagnosis,
      :measurement,
      :procedure,
      :vaccination,
      :prescription,
      :dose,
      :placement,
      :group,
      :behaviour,
      :general
    ]

  @medical [
    :examination,
    :diagnosis,
    :measurement,
    :procedure,
    :vaccination,
    :prescription,
    :dose
  ]

  @doc "The kinds that are a part of the medical history."
  def medical, do: @medical

  @doc "Whether a kind is a part of the medical history."
  def medical?(kind), do: kind in @medical
end
