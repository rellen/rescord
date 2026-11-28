defmodule Rescord.Ruby.Changes.KindDefaults do
  @moduledoc """
  Gives a new provider the values of its kind that the root user left
  empty: the model of Anthropic, the address of Ollama, the limit of a
  request. So the row says what Ruby uses.
  """

  use Ash.Resource.Change

  alias Rescord.Ruby.LLM.Profile

  @impl true
  def change(changeset, _opts, _context) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)

    Enum.reduce(Profile.defaults(kind), changeset, fn {name, value}, changeset ->
      case Ash.Changeset.get_attribute(changeset, name) do
        nil -> Ash.Changeset.force_change_attribute(changeset, name, value)
        _given -> changeset
      end
    end)
  end
end
