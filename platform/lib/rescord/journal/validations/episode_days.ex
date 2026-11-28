defmodule Rescord.Journal.Validations.EpisodeDays do
  @moduledoc """
  The days of an episode are days that happened, in their order: the first
  day is not after today, and the last day is not after today and not
  before the first day.

  Today is the date in the time zone of the organisation (ADR 0026), at the
  instant of the write.
  """

  use Ash.Resource.Validation

  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    started_on = Ash.Changeset.get_attribute(changeset, :started_on)
    ended_on = Ash.Changeset.get_attribute(changeset, :ended_on)
    today = today(changeset)

    cond do
      after?(started_on, today) ->
        {:error, field: :started_on, message: "cannot be after today"}

      after?(ended_on, today) ->
        {:error, field: :ended_on, message: "cannot be after today"}

      after?(started_on, ended_on) ->
        {:error, field: :ended_on, message: "cannot be before the first day"}

      true ->
        :ok
    end
  end

  defp after?(%Date{} = one, %Date{} = other), do: Date.compare(one, other) == :gt
  defp after?(_one, _other), do: false

  @doc """
  The date of today for a write. The write happens as of an instant. That
  instant, and not the clock of the server, says what today is in the
  organisation.
  """
  def today(%{as_of: %DateTime{} = instant, tenant: tenant}),
    do: Rescord.Accounts.local_date(tenant, instant)

  def today(%{tenant: tenant}), do: Rescord.Accounts.today(tenant)
end
