defmodule Rescord.Photos.Changes.StorePhoto do
  @moduledoc """
  Makes a new photo safe to keep, and puts it in the store with its
  thumbnail after the write (ADR 0055).

  `Rescord.Images.prepare/1` reads the type from the first bytes, turns the
  photo as its EXIF says, and removes its metadata, the GPS position with
  the rest. The change refuses an empty file, a file of more than
  `max_size/0` bytes, and a file that is not a photo that Rescord can read.

  The date is the one that the person gave. With none, it is the date that
  the camera recorded, and with no such date, or with one after today, it
  is the day of the action in the time zone of the organisation.

  The keys are `<organisation id>/photos/<id>` and
  `<organisation id>/thumbnails/<id>`. The files go into the store in an
  `after_action` hook, in the transaction: a fault of the store returns an
  error, and the record is not written.
  """

  use Ash.Resource.Change

  alias Rescord.{Accounts, Images, Storage}
  alias Rescord.Storage.Errors.RefusedFile

  @max_size 20_000_000

  @doc "The largest photo that a person can send, in bytes: 20 MB."
  def max_size, do: @max_size

  # The change reads the instant of the action, and not the clock, when the
  # action has one.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :content) do
      "" ->
        refuse(changeset, RefusedFile.exception(reason: :empty))

      content when byte_size(content) > @max_size ->
        refuse(changeset, RefusedFile.exception(reason: :too_large))

      content when is_binary(content) ->
        prepare(changeset, content)

      _none ->
        changeset
    end
  end

  defp prepare(changeset, content) do
    case Images.prepare(content) do
      {:ok, photo} -> store(changeset, photo)
      {:error, error} -> refuse(changeset, error)
    end
  end

  defp refuse(changeset, %RefusedFile{} = error),
    do: Ash.Changeset.add_error(changeset, %{error | field: :content})

  defp store(changeset, photo) do
    # The id is not set when a change runs, and the keys name it.
    id = Ash.Changeset.get_attribute(changeset, :id) || Ash.UUID.generate()
    organisation = Accounts.organisation_of(changeset.to_tenant)
    key = Storage.key(organisation.id, ["photos", id])
    thumbnail_key = Storage.key(organisation.id, ["thumbnails", id])

    changeset
    |> Ash.Changeset.force_change_attribute(:id, id)
    |> Ash.Changeset.force_change_attribute(:content_type, photo.content_type)
    |> Ash.Changeset.force_change_attribute(:size, byte_size(photo.bytes))
    |> Ash.Changeset.force_change_attribute(:key, key)
    |> Ash.Changeset.force_change_attribute(:thumbnail_key, thumbnail_key)
    |> date(photo.taken_at, organisation)
    |> Ash.Changeset.after_action(fn _changeset, record ->
      with :ok <- Storage.put(key, photo.bytes, photo.content_type),
           :ok <- Storage.put(thumbnail_key, photo.thumbnail, "image/webp") do
        {:ok, record}
      else
        {:error, _reason} ->
          {:error,
           Ash.Error.Changes.InvalidArgument.exception(
             field: :content,
             message: "did not reach the store. Try again later"
           )}
      end
    end)
  end

  # A camera with a wrong clock can record a date after today, and then the
  # photo has the date of today.
  defp date(changeset, taken_at, organisation) do
    case Ash.Changeset.get_attribute(changeset, :taken_on) do
      nil ->
        today = Accounts.local_date(organisation, instant(changeset))

        on =
          case taken_at do
            %NaiveDateTime{} = at -> Enum.min([NaiveDateTime.to_date(at), today], Date)
            nil -> today
          end

        Ash.Changeset.force_change_attribute(changeset, :taken_on, on)

      _given ->
        changeset
    end
  end

  defp instant(%{as_of: %DateTime{} = instant}), do: instant
  defp instant(_changeset), do: DateTime.utc_now()
end
