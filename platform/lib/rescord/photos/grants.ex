defmodule Rescord.Photos.Grants do
  @moduledoc """
  What a role can do with the photos of the residents (ADR 0024 and
  ADR 0055).

  Each role reads the photos, the albums and the profile pictures. The
  photos are a part of the care of the residents, so the power `:residents`
  adds a photo, uses a photo of the journal, changes the caption and the
  date of each photo, makes and removes the albums, puts a photo in an
  album, and chooses the profile picture. It removes the photos that the
  person added: the scope `own`. The power `:remove_residents` removes each
  photo.
  """

  @behaviour Rescord.Accounts.Grants

  import Ash.Expr, only: [expr: 1, actor: 1]

  alias Rescord.Photos.{Album, AlbumPhoto, Photo, ProfilePhoto}

  @impl true
  def reads,
    do: for(resource <- [Photo, Album, AlbumPhoto, ProfilePhoto], do: {resource, :read, :all})

  @impl true
  def powers do
    %{
      residents: [
        {Photo, :add, :all},
        {Photo, :adopt, :all},
        {Photo, :describe, :all},
        {Photo, :remove, :own},
        {Album, :make, :all},
        {Album, :rename, :all},
        {Album, :remove, :all},
        {AlbumPhoto, :add, :all},
        {AlbumPhoto, :take_out, :all},
        {ProfilePhoto, :choose, :all},
        {ProfilePhoto, :change, :all},
        {ProfilePhoto, :clear, :all}
      ],
      remove_residents: [{Photo, :remove, :all}]
    }
  end

  @impl true
  def filter(Photo, :own), do: expr(author_id == ^actor(:id))
  def filter(_resource, _scope), do: nil
end
