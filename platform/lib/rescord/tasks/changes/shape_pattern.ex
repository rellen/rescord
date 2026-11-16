defmodule Rescord.Tasks.Changes.ShapePattern do
  @moduledoc """
  Puts the pattern of a routine in one shape, and refuses a pattern with a
  fact that is not there.

  The shape: the times in order with each one time; the days of the week in
  order, and only for the pattern `:weekly`; the number only for the
  patterns `:interval` and `:monthly`.

  The rules:

    * a routine has from 1 to 12 times;
    * `:weekly` has one day of the week or more, each from 1 (Monday) to 7;
    * `:interval` has a number of days from 1 to 366;
    * `:monthly` has a number of months from 1 to 36;
    * the last day is not before the first day.
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @max_times 12

  @impl true
  def change(changeset, _opts, _context) do
    pattern = Changeset.get_attribute(changeset, :pattern)

    changeset
    |> shape_times()
    |> shape_weekdays(pattern)
    |> shape_every(pattern)
    |> check_days()
  end

  defp shape_times(changeset) do
    times =
      changeset
      |> Changeset.get_attribute(:times)
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.sort(Time)

    changeset = Changeset.force_change_attribute(changeset, :times, times)

    cond do
      times == [] -> error(changeset, :times, "needs one time or more")
      length(times) > @max_times -> error(changeset, :times, "can have #{@max_times} at most")
      true -> changeset
    end
  end

  defp shape_weekdays(changeset, :weekly) do
    weekdays =
      changeset |> Changeset.get_attribute(:weekdays) |> List.wrap() |> Enum.uniq() |> Enum.sort()

    changeset = Changeset.force_change_attribute(changeset, :weekdays, weekdays)

    cond do
      weekdays == [] -> error(changeset, :weekdays, "needs one day of the week or more")
      Enum.any?(weekdays, &(&1 not in 1..7)) -> error(changeset, :weekdays, "are from 1 to 7")
      true -> changeset
    end
  end

  defp shape_weekdays(changeset, _pattern),
    do: Changeset.force_change_attribute(changeset, :weekdays, [])

  defp shape_every(changeset, pattern) when pattern in [:interval, :monthly] do
    {most, unit} = if pattern == :interval, do: {366, "days"}, else: {36, "months"}

    case Changeset.get_attribute(changeset, :every) do
      every when is_integer(every) and every >= 1 and every <= most -> changeset
      _other -> error(changeset, :every, "is a number of #{unit} from 1 to #{most}")
    end
  end

  defp shape_every(changeset, _pattern),
    do: Changeset.force_change_attribute(changeset, :every, nil)

  defp check_days(changeset) do
    starts_on = Changeset.get_attribute(changeset, :starts_on)
    ends_on = Changeset.get_attribute(changeset, :ends_on)

    if starts_on && ends_on && Date.compare(ends_on, starts_on) == :lt,
      do: error(changeset, :ends_on, "cannot be before the first day"),
      else: changeset
  end

  defp error(changeset, field, message),
    do: Changeset.add_error(changeset, field: field, message: message)
end
