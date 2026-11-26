defmodule Rescord.Photos.Validations.NotAfterToday do
  @moduledoc """
  Refuses a photo whose date is after the day of the action, in the time
  zone of the organisation: a photo shows a day that has come.
  """

  use Ash.Resource.Validation

  alias Rescord.Accounts

  # The validation reads the instant of the action, and not the clock, when
  # the action has one.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    with %Date{} = on <- Ash.Changeset.get_attribute(changeset, :taken_on),
         today = Accounts.local_date(changeset.to_tenant, instant(changeset)),
         :gt <- Date.compare(on, today) do
      {:error, field: :taken_on, message: "cannot be after today"}
    else
      _fine -> :ok
    end
  end

  defp instant(%{as_of: %DateTime{} = instant}), do: instant
  defp instant(_changeset), do: DateTime.utc_now()
end
