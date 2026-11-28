defmodule Rescord.Export.Errors.InvalidDate do
  @moduledoc """
  The date of an export that Rescord does not take (ADR 0077, E2). The
  reason is `:after_today`, or `:not_a_date` for a value that is not a
  `Date`.
  """

  use Splode.Error, fields: [reason: :not_a_date], class: :invalid

  @typedoc "Why the date is refused."
  @type reason :: :after_today | :not_a_date

  @impl true
  def message(%{reason: :after_today}), do: "The date is after today."
  def message(%{reason: _not_a_date}), do: "The date is not a date."
end
