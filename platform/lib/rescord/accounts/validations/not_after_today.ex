defmodule Rescord.Accounts.Validations.NotAfterToday do
  @moduledoc """
  A date of a thing that happened is not after today: the day of an
  arrival, of a photo, of a payment. The option `:attribute` names the date.
  Each domain uses this one validation (ADR 0086).

  Today is the date in the time zone of the organisation (ADR 0026). A
  write to a temporal resource happens as of an instant, and that instant,
  and not the clock of the server, says what today is. A resource that is
  not temporal has no such instant, and then the clock says it.

  A record with no date passes: another rule says whether the date must be
  there.
  """

  use Ash.Resource.Validation

  alias Rescord.Accounts

  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def init(opts) do
    case opts[:attribute] do
      attribute when is_atom(attribute) and not is_nil(attribute) -> {:ok, opts}
      _other -> {:error, "attribute must be the name of a date attribute"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    attribute = opts[:attribute]

    case Ash.Changeset.get_attribute(changeset, attribute) do
      %Date{} = date ->
        if Date.compare(date, today(changeset)) == :gt do
          {:error, field: attribute, message: "cannot be after today"}
        else
          :ok
        end

      _no_date ->
        :ok
    end
  end

  defp today(%{as_of: %DateTime{} = instant, tenant: tenant}),
    do: Accounts.local_date(tenant, instant)

  defp today(%{tenant: tenant}), do: Accounts.today(tenant)
end
