defmodule Rescord.Usage.Changes.NoteToken do
  @moduledoc """
  Writes the hint of a new token, its last four characters, and the time
  that it was set. They are in the clear, so that the page says "ends in
  3f9k" and decrypts nothing.

  It reads the argument `token` while the changeset is built. AshCloak
  encrypts the argument in a hook before the action.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :token) do
      {:ok, token} when is_binary(token) and token != "" ->
        changeset
        |> Ash.Changeset.force_change_attribute(:token_hint, hint(token))
        |> Ash.Changeset.force_change_attribute(:token_set_at, DateTime.utc_now())

      _none ->
        changeset
    end
  end

  # A short token would be its own hint, so it gets none.
  defp hint(token) do
    if String.length(token) >= 12, do: String.slice(token, -4, 4)
  end
end
