defmodule Rescord.Ruby.Changes.NoteKey do
  @moduledoc """
  Writes the hint of a new key, its last four characters, and the time that
  it was set. They are in the clear, so that a page says "ends in 3f9k"
  and decrypts nothing.

  It reads the argument `api_key` while the changeset is built. AshCloak
  encrypts the argument in a hook before the action, and then takes it out
  of the changeset.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :api_key) do
      {:ok, key} when is_binary(key) and key != "" ->
        changeset
        |> Ash.Changeset.force_change_attribute(:key_hint, hint(key))
        |> Ash.Changeset.force_change_attribute(:key_set_at, DateTime.utc_now())

      _none ->
        changeset
    end
  end

  # A short key would be its own hint, so it gets none.
  defp hint(key) do
    if String.length(key) >= 12, do: String.slice(key, -4, 4)
  end
end
