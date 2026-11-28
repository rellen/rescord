defmodule Rescord.Accounts.Validations.KnownLocale do
  @moduledoc """
  The locale of an organisation is one that Rescord offers, for example
  `en-AU` (ADR 0075).
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :locale) do
      nil ->
        :ok

      locale ->
        if Rescord.Accounts.locale?(locale) do
          :ok
        else
          {:error, field: :locale, message: "is not a language and region that Rescord offers"}
        end
    end
  end
end
