defmodule Rescord.Tasks.RoutinePattern do
  @moduledoc """
  How a routine repeats (`docs/domain.md`, section 5.7, and ADR 0033):

    * `:daily` - each day;
    * `:weekly` - on given days of the week;
    * `:interval` - every number of days, from the first day of the routine;
    * `:monthly` - every number of months, on the day of the month of the
      first day of the routine.

  A page shows the words of `RescordWeb.TaskWords`, and never the atom.
  """

  use Ash.Type.Enum, values: [:daily, :weekly, :interval, :monthly]
end
