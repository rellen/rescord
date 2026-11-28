defmodule Rescord.Accounts.Changes.TrimTaxName do
  @moduledoc """
  Trims the name of the tax of an organisation (ADR 0089). An empty name is
  no name: the organisation then records no tax on an expense. A name is
  one line of text, such as `GST` or `VAT`.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_change(changeset, :tax_name) do
      {:ok, name} when is_binary(name) -> put(changeset, String.trim(name))
      _no_change -> changeset
    end
  end

  defp put(changeset, ""), do: Ash.Changeset.force_change_attribute(changeset, :tax_name, nil)

  defp put(changeset, name) do
    if String.match?(name, ~r/\p{C}/u) do
      Ash.Changeset.add_error(changeset,
        field: :tax_name,
        message: "must be one line of text, such as GST"
      )
    else
      Ash.Changeset.force_change_attribute(changeset, :tax_name, name)
    end
  end
end
