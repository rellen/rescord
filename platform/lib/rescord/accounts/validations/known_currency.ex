defmodule Rescord.Accounts.Validations.KnownCurrency do
  @moduledoc """
  The currency of an organisation is the code of a currency that people pay
  with now, for example `AUD` (ADR 0082).
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :currency) do
      code when is_binary(code) ->
        if Rescord.Accounts.currency?(code) do
          :ok
        else
          {:error, field: :currency, message: "is not a currency that Rescord knows, such as AUD"}
        end

      _not_given ->
        :ok
    end
  end
end
