defmodule Rescord.Ruby.Changes.AddCounts do
  @moduledoc """
  What `add` of `Rescord.Ruby.Usage` does to a row that is there: each
  count of the input is added to the count of the row, in the statement
  itself, so two replies that end at one moment both count.
  """

  use Ash.Resource.Change

  import Ash.Expr

  alias Rescord.Ruby.Usage

  @impl true
  def change(changeset, _opts, _context) do
    Enum.reduce(Usage.counts(), changeset, fn count, changeset ->
      added = Ash.Changeset.get_attribute(changeset, count) || 0
      Ash.Changeset.atomic_update(changeset, count, {:atomic, expr(^ref(count) + ^added)})
    end)
  end
end
