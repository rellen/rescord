defmodule Rescord.Expenses.Validations.NotAfterToday do
  @moduledoc """
  A date of an expense is not after today in the time zone of the
  organisation: the date of the payment, and the date on which the
  organisation paid the member back. The option `:attribute` names the date.
  """

  use Ash.Resource.Validation

  alias Rescord.Accounts

  @impl true
  def validate(changeset, opts, _context) do
    attribute = Keyword.fetch!(opts, :attribute)

    case Ash.Changeset.get_attribute(changeset, attribute) do
      %Date{} = date ->
        if Date.compare(date, Accounts.today(changeset.to_tenant)) == :gt,
          do: {:error, field: attribute, message: "cannot be after today"},
          else: :ok

      _no_date ->
        :ok
    end
  end
end
