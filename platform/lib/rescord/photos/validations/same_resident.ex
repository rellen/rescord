defmodule Rescord.Photos.Validations.SameResident do
  @moduledoc """
  Refuses a tie between two records of two residents: a photo in an album
  of another resident, or a profile picture that shows another resident
  (ADR 0055).

  The validation reads the photo, and the album when the tie has one, as of
  the instant of the action and with no decision of a policy: it checks
  that the data fit together, and the policy of the tie decides who can
  write it.
  """

  use Ash.Resource.Validation

  alias Rescord.Photos.{Album, Photo}

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    options = options(changeset)
    photo_id = Ash.Changeset.get_attribute(changeset, :photo_id)

    with {:ok, resident_id} <- resident_of(changeset, options),
         true <- is_binary(photo_id),
         {:ok, %{resident_id: ^resident_id}} <- Ash.get(Photo, photo_id, options) do
      :ok
    else
      # The other validations of the action say what is missing.
      :missing -> :ok
      false -> :ok
      _other -> {:error, field: :photo_id, message: "is not a photo of this resident"}
    end
  end

  # The resident that the photo must show: the one of the album, or the one
  # that the profile picture is of.
  defp resident_of(changeset, options) do
    case Ash.Changeset.get_attribute(changeset, :album_id) do
      album_id when is_binary(album_id) ->
        case Ash.get(Album, album_id, options) do
          {:ok, %{resident_id: resident_id}} -> {:ok, resident_id}
          _no_album -> {:error, :no_album}
        end

      _no_album ->
        case Ash.Changeset.get_attribute(changeset, :resident_id) do
          resident_id when is_binary(resident_id) -> {:ok, resident_id}
          _none -> :missing
        end
    end
  end

  defp options(changeset) do
    base = [tenant: changeset.tenant, authorize?: false, not_found_error?: false]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
