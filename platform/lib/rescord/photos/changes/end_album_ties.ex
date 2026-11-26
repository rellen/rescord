defmodule Rescord.Photos.Changes.EndAlbumTies do
  @moduledoc """
  Takes each photo out of an album that a person removes, after the
  removal, in the same transaction and as of the same instant (ADR 0036).
  The photos stay. The policy of the album decided that the actor can
  remove it, so the change ends the ties with no second decision.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Photos.AlbumPhoto

  # The change reads and writes through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, album ->
      options = Rescord.Photos.Changes.Ties.options(changeset, context)
      id = album.id
      ties = AlbumPhoto |> Ash.Query.filter(album_id == ^id) |> Ash.read!(options)
      Rescord.Photos.Changes.Ties.finish(Enum.map(ties, &{&1, :take_out}), album, options)
    end)
  end
end
