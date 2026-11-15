defmodule Rescord.Residents.Validations.NotAfterToday do
  @moduledoc """
  A date of a fact that happened is not after today.

  Rescord does not know the time zone of an organisation. Today is thus the
  latest date that any place has at the instant of the write: the date in
  UTC, and one day more.
  """

  use Ash.Resource.Validation

  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def init(opts) do
    if is_atom(opts[:attribute]), do: {:ok, opts}, else: {:error, "attribute must be an atom"}
  end

  @impl true
  def validate(changeset, opts, _context) do
    attribute = opts[:attribute]

    case Ash.Changeset.get_attribute(changeset, attribute) do
      %Date{} = date ->
        if Date.compare(date, latest_today(changeset)) == :gt do
          {:error, field: attribute, message: "cannot be after today"}
        else
          :ok
        end

      _other ->
        :ok
    end
  end

  # The write happens as of an instant. That instant, and not the clock of
  # the server, says what today is.
  defp latest_today(%{as_of: %DateTime{} = instant}),
    do: instant |> DateTime.to_date() |> Date.add(1)

  defp latest_today(_changeset), do: Date.add(Date.utc_today(), 1)
end
