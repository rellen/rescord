defmodule Rescord.Photos.Changes.EndPhotoTies do
  @moduledoc """
  Ends the ties of a photo that a person removes: each album that holds it,
  and the profile picture of its resident when the photo is that picture
  (ADR 0036). The change ends them after the removal, in the same
  transaction and as of the same instant, so their history stays.

  The policy of the photo decided that the actor can remove it. The ties
  are a part of that action, so the change ends them with no second
  decision, and names the actor for the paper trail.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Photos.{AlbumPhoto, ProfilePhoto}

  # The change reads and writes through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, photo ->
      options = Rescord.Photos.Changes.Ties.options(changeset, context)
      id = photo.id

      albums = AlbumPhoto |> Ash.Query.filter(photo_id == ^id) |> Ash.read!(options)
      profiles = ProfilePhoto |> Ash.Query.filter(photo_id == ^id) |> Ash.read!(options)

      Rescord.Photos.Changes.Ties.finish(
        Enum.map(albums, &{&1, :take_out}) ++ Enum.map(profiles, &{&1, :clear}),
        photo,
        options
      )
    end)
  end
end
