defmodule Rescord.Photos do
  @moduledoc """
  The photos of each resident: the photos that the members add, each with
  a caption and a date, the albums that group them, and the profile
  picture (ADR 0055).

  The photos of the journal entries of a resident are a part of its photos
  too. `photos_of/2` gives both: a photo of the journal shows with its entry,
  and becomes a record of its own (`adopt/2`) when a person puts it in an
  album or makes it the profile picture.

  Each resource here is temporal (ADR 0012). Pass `as_of:` in the options
  of a function to read the photos as they were at a past instant.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.{Journal, Storage}
  alias Rescord.Photos.{Album, AlbumPhoto, Photo, ProfilePhoto}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Residents, Rescord.Journal]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Photos.Photo do
      define :photo, action: :read, get_by: [:id], not_found_error?: false
      define :add_photo, action: :add
      define :describe_photo, action: :describe
      define :remove_photo, action: :remove
    end

    resource Rescord.Photos.Album do
      define :album, action: :read, get_by: [:id], not_found_error?: false
      define :make_album, action: :make
      define :rename_album, action: :rename, args: [:name]
      define :remove_album, action: :remove
    end

    resource Rescord.Photos.AlbumPhoto do
      define :add_to_album, action: :add
      define :take_out_of_album, action: :take_out
    end

    resource Rescord.Photos.ProfilePhoto
  end

  @typedoc """
  One photo of a resident on its page: a photo record, or a photo of a
  journal entry that is no record yet (`photo: nil`).
  """
  @type item :: %{
          photo: Ash.Resource.record() | nil,
          attachment: Ash.Resource.record() | nil,
          entry_id: String.t() | nil,
          taken_on: Date.t(),
          caption: String.t() | nil,
          album_ids: [String.t()]
        }

  @doc """
  The photos of a resident, the newest first by their dates: each photo
  record with its albums, and each photo of its journal entries that is no
  record yet, with the date of its entry. Each one is an `t:item/0`.

  A photo of an attachment that is gone is left out. The tenant in `opts`
  gives the time zone of the dates of the entries.
  """
  @spec photos_of(String.t(), keyword) :: {:ok, [item]} | {:error, term}
  def photos_of(resident_id, opts \\ []) do
    with {:ok, photos} <-
           Photo
           |> Ash.Query.filter(resident_id == ^resident_id)
           |> Ash.Query.load([:attachment, :album_photos])
           |> Ash.Query.sort(taken_on: :desc, id: :asc)
           |> Ash.read(opts),
         {:ok, entries} <- Journal.entries(resident_id, opts),
         {:ok, files} <- Journal.attachments_of(Enum.map(entries, & &1.id), opts) do
      kept =
        for photo <- photos, is_nil(photo.attachment_id) or not is_nil(photo.attachment) do
          %{
            photo: photo,
            attachment: photo.attachment,
            entry_id: photo.attachment && photo.attachment.entry_id,
            taken_on: photo.taken_on,
            caption: photo.caption,
            album_ids: Enum.map(photo.album_photos, & &1.album_id)
          }
        end

      adopted = MapSet.new(photos, & &1.attachment_id)

      journal =
        for entry <- entries,
            attachment <- Map.get(files, entry.id, []),
            String.starts_with?(attachment.content_type, "image/"),
            not MapSet.member?(adopted, attachment.id) do
          %{
            photo: nil,
            attachment: attachment,
            entry_id: entry.id,
            taken_on: Rescord.Accounts.local_date(opts[:tenant], entry.happened_at),
            caption: nil,
            album_ids: []
          }
        end

      {:ok, Enum.sort_by(kept ++ journal, & &1.taken_on, {:desc, Date})}
    end
  end

  @doc "The albums of a resident, by their names."
  def albums(resident_id, opts \\ []) do
    Album
    |> Ash.Query.filter(resident_id == ^resident_id)
    |> Ash.Query.sort(name: :asc, id: :asc)
    |> Ash.read(opts)
  end

  @doc """
  The photo record of a photo of the journal: the one that is there, or a
  new one. A page calls this before it puts a photo of the journal in an
  album or makes it the profile picture.
  """
  def adopt(attachment_id, opts \\ []) do
    existing =
      Photo
      |> Ash.Query.filter(attachment_id == ^attachment_id)
      |> Ash.read(opts)

    case existing do
      {:ok, [photo | _]} ->
        {:ok, photo}

      {:ok, []} ->
        Photo
        |> Ash.Changeset.for_create(:adopt, %{attachment_id: attachment_id}, opts)
        |> Ash.create()

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Saves what a person says about a photo of `photos_of/2`, in one
  transaction: its caption, its date, and the albums of its resident that
  hold it. A photo of the journal becomes a record of its own first
  (`adopt/2`). A date of `nil` keeps the date that the photo has.

  Returns the photo record.
  """
  @spec keep(item, %{caption: String.t() | nil, taken_on: term, album_ids: [String.t()]}, keyword) ::
          {:ok, Ash.Resource.record()} | {:error, term}
  def keep(item, %{caption: caption, taken_on: taken_on, album_ids: album_ids}, opts \\ []) do
    Ash.transact(
      [Photo, AlbumPhoto],
      fn ->
        with {:ok, photo} <- record_of(item, opts),
             {:ok, photo} <- describe(photo, caption, taken_on, opts),
             :ok <- place(photo, album_ids, opts) do
          {:ok, photo}
        end
      end,
      tenant: opts[:tenant]
    )
    |> case do
      {:ok, {:ok, photo}} -> {:ok, photo}
      {:ok, {:error, error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  @doc "The photo record of a photo of `photos_of/2`: the one that it has, or a new one."
  @spec record_of(item, keyword) :: {:ok, Ash.Resource.record()} | {:error, term}
  def record_of(%{photo: %Photo{} = photo}, _opts), do: {:ok, photo}
  def record_of(%{attachment: %{id: id}}, opts), do: adopt(id, opts)

  defp describe(photo, caption, taken_on, opts) do
    changes =
      if is_nil(taken_on),
        do: %{caption: caption},
        else: %{caption: caption, taken_on: taken_on}

    if caption == photo.caption and (is_nil(taken_on) or same_date?(taken_on, photo.taken_on)),
      do: {:ok, photo},
      else: describe_photo(photo, changes, opts)
  end

  defp same_date?(%Date{} = one, %Date{} = other), do: Date.compare(one, other) == :eq

  defp same_date?(text, %Date{} = other) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> same_date?(date, other)
      {:error, _reason} -> false
    end
  end

  defp same_date?(_other, _date), do: false

  @doc """
  The profile picture of a resident, as its photo, or `nil` when it has
  none, or when the actor cannot read it.
  """
  def profile_photo(resident_id, opts \\ []) do
    case profile_photos([resident_id], opts) do
      {:ok, photos} -> {:ok, Map.get(photos, resident_id)}
      {:error, error} -> {:error, error}
    end
  end

  @doc "The profile pictures of residents, as a map from the id of each resident to its photo."
  def profile_photos(resident_ids, opts \\ []) when is_list(resident_ids) do
    ProfilePhoto
    |> Ash.Query.filter(resident_id in ^resident_ids)
    |> read_profiles(opts)
  end

  @doc """
  The profile picture of each resident of the organisation that has one, as
  a map from the id of the resident to its photo. The list of the residents
  reads them all at once: Cinder reads the residents, and their pictures
  are in this domain, which the residents do not know (ADR 0055).
  """
  def all_profile_photos(opts \\ []), do: read_profiles(ProfilePhoto, opts)

  defp read_profiles(query, opts) do
    query
    |> Ash.Query.load(photo: [:attachment])
    |> Ash.read(opts)
    |> case do
      {:ok, profiles} ->
        {:ok,
         for(
           profile <- profiles,
           photo = profile.photo,
           photo && (is_nil(photo.attachment_id) or photo.attachment),
           into: %{},
           do: {profile.resident_id, photo}
         )}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Makes a photo the profile picture of its resident: a new record, or a new
  version of the one that is there.
  """
  def set_profile_photo(%Photo{} = photo, opts \\ []) do
    ProfilePhoto
    |> Ash.Query.filter(resident_id == ^photo.resident_id)
    |> Ash.read(opts)
    |> case do
      {:ok, [%{photo_id: id} = profile | _]} when id == photo.id ->
        {:ok, profile}

      {:ok, [profile | _]} ->
        profile
        |> Ash.Changeset.for_update(:change, %{photo_id: photo.id}, opts)
        |> Ash.update()

      {:ok, []} ->
        ProfilePhoto
        |> Ash.Changeset.for_create(
          :choose,
          %{resident_id: photo.resident_id, photo_id: photo.id},
          opts
        )
        |> Ash.create()

      {:error, error} ->
        {:error, error}
    end
  end

  @doc "Leaves a resident with no profile picture."
  def clear_profile_photo(resident_id, opts \\ []) do
    ProfilePhoto
    |> Ash.Query.filter(resident_id == ^resident_id)
    |> Ash.read(opts)
    |> case do
      {:ok, [profile | _]} -> Ash.destroy(profile, [action: :clear] ++ opts)
      {:ok, []} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Puts a photo in the albums that a person chose, and takes it out of the
  others of its resident, in one transaction.
  """
  def place_in_albums(%Photo{} = photo, album_ids, opts \\ []) when is_list(album_ids) do
    Ash.transact([AlbumPhoto], fn -> place(photo, album_ids, opts) end, tenant: opts[:tenant])
    |> case do
      {:ok, :ok} -> :ok
      {:ok, {:error, error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  defp place(photo, album_ids, opts) do
    with {:ok, ties} <- AlbumPhoto |> Ash.Query.filter(photo_id == ^photo.id) |> Ash.read(opts),
         :ok <- take_out(Enum.reject(ties, &(&1.album_id in album_ids)), opts) do
      put_into(album_ids -- Enum.map(ties, & &1.album_id), photo, opts)
    end
  end

  defp take_out(ties, opts) do
    Enum.reduce_while(ties, :ok, fn tie, :ok ->
      case take_out_of_album(tie, opts) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp put_into(album_ids, photo, opts) do
    Enum.reduce_while(album_ids, :ok, fn album_id, :ok ->
      case add_to_album(%{album_id: album_id, photo_id: photo.id}, opts) do
        {:ok, _tie} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc """
  A photo and the bytes of one of its files, `:photo` or `:thumbnail`, when
  the actor can read the photo and the store has the file. A photo of an
  attachment that is gone, and an old photo of the journal with no
  thumbnail, have no such file.
  """
  @spec photo_file(String.t(), :photo | :thumbnail, keyword) ::
          {:ok, map, binary} | {:error, :not_found | term}
  def photo_file(id, which, opts \\ []) when which in [:photo, :thumbnail] do
    with {:ok, %{} = photo} <- photo(id, [load: [:attachment]] ++ opts),
         true <- is_nil(photo.attachment_id) or not is_nil(photo.attachment),
         key when is_binary(key) <- if(which == :photo, do: photo.key, else: photo.thumbnail_key),
         {:ok, bytes} <- Storage.get(key) do
      {:ok, photo, bytes}
    else
      {:error, error} -> {:error, error}
      _no_file -> {:error, :not_found}
    end
  end

  @doc """
  Each key of the store that a photo of the organisation names: the photo
  and its thumbnail, of each photo, the removed ones too
  (`Rescord.Storage.Named`, ADR 0091). A photo of a journal entry names
  the keys of its attachment. It reads the table with no actor, for
  `bin/check-files`, and no page calls it.
  """
  @spec file_keys(String.t()) :: [Storage.Named.entry()]
  def file_keys(organisation_id), do: Storage.Named.keys(Photo, "photo", organisation_id)

  @doc "The largest photo that a person can send, in bytes."
  defdelegate max_photo_size(), to: Rescord.Photos.Changes.StorePhoto, as: :max_size

  @doc "Whether a role can run an action on the photos at all, such as `{Photo, :add}`."
  @spec role_can?(atom | Ash.Resource.record() | nil, :photo | :album | :profile, atom) :: boolean
  def role_can?(role, subject, action) do
    resource =
      case subject do
        :photo -> Photo
        :album -> Album
        :profile -> ProfilePhoto
      end

    Rescord.Accounts.granted?(role, resource, action)
  end

  @doc """
  Whether a role can remove a photo: each photo with the power
  `:remove_residents`, and the photos that the person added with the power
  `:residents`. A page asks this to decide what to show.
  """
  @spec can_remove_photo?(term, map, map) :: boolean
  def can_remove_photo?(:root, _user, _photo), do: true

  def can_remove_photo?(role, %{id: user_id}, %{author_id: author_id}) do
    case Rescord.Accounts.Grants.scope(role, Photo, :remove) do
      {:ok, :all} -> true
      {:ok, :own} -> user_id == author_id
      :none -> false
    end
  end
end
