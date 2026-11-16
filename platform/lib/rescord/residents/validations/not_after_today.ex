defmodule Rescord.Residents.Validations.NotAfterToday do
  @moduledoc """
  A date of a fact that happened is not after today.

  Today is the date in the time zone of the organisation (ADR 0026), at the
  instant of the write.
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
        if Date.compare(date, today(changeset)) == :gt do
          {:error, field: attribute, message: "cannot be after today"}
        else
          :ok
        end

      _other ->
        :ok
    end
  end

  # The write happens as of an instant. That instant, and not the clock of
  # the server, says what today is in the organisation.
  defp today(%{as_of: %DateTime{} = instant, tenant: tenant}),
    do: Rescord.Accounts.local_date(tenant, instant)

  defp today(%{tenant: tenant}), do: Rescord.Accounts.today(tenant)
end
