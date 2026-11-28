defmodule Rescord.Notifications.Changes.NewTopic do
  @moduledoc """
  A new random name for a topic of ntfy: 32 characters of letters and
  digits from 24 random bytes, which nobody guesses. ntfy takes letters,
  digits, `-` and `_` in a topic.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    topic =
      :crypto.strong_rand_bytes(24)
      |> Base.url_encode64(padding: false)
      |> String.replace(["-", "_"], "x")

    AshCloak.encrypt_and_set(changeset, :topic, topic)
  end
end
