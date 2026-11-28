defmodule Rescord.Accounts.Errors.InvalidTime do
  @moduledoc """
  A time that a member gave, from the text of a form, that Rescord does not
  take (ADR 0077, E2): `Rescord.Accounts.instant/2` and
  `Rescord.Accounts.local_instant/2` return it.

  The reason says what is wrong, and never holds the text:

  - `:after_now`: the time of a thing that happened is after now.
  - `:not_a_time`: the text is not a date and a time, or the clocks of the
    time zone of the organisation skip that time or show it twice.
  """

  use Splode.Error, fields: [reason: :not_a_time], class: :invalid

  @typedoc "Why the time is refused."
  @type reason :: :after_now | :not_a_time

  @impl true
  def message(%{reason: :after_now}), do: "The time cannot be after now"
  def message(%{reason: _not_a_time}), do: "The time is not a date and a time of this time zone"
end
