defmodule RescordWeb.PhotoComponents do
  @moduledoc """
  The parts of the page of the photos of a resident (ADR 0037 and
  ADR 0055): its profile picture, its albums, the form that adds photos,
  and the grid of the photos with the form of each one; and the small
  profile picture of each resident in the list of the residents.

  A photo is an item of `Rescord.Photos.photos_of/2`: a photo record, or a
  photo of a journal entry that is no record yet. Each part names an item
  by its reference (`ref/1`), and the page finds the item again from that
  reference among the items that it has.
  """

  use RescordWeb, :html

  alias RescordWeb.{JournalComponents, ResidentWords, UploadWords}

  @doc """
  The profile picture of a resident, with a link to its photos, or nothing
  when it has none.
  """
  attr :photo, :any, required: true
  attr :organisation, :any, required: true
  attr :resident, :any, required: true

  def profile(assigns) do
    ~H"""
    <figure :if={@photo} data-profile id="profile-photo">
      <a href={open_url(@organisation, @photo)}>
        <img
          src={thumbnail_url(@organisation, @photo)}
          alt={@photo.caption || "The profile picture of #{name(@resident)}"}
        />
      </a>
      <figcaption>Profile picture</figcaption>
    </figure>
    """
  end

  @doc """
  The small profile picture of a resident in the list of the residents, or
  the first letter of its name in its place when it has none. It goes
  beside the name, inside the link, so it is only decoration: the name says
  which resident it is.
  """
  attr :url, :string, default: nil, doc: "the link to the thumbnail, or nil"
  attr :name, :string, default: nil, doc: "the name of the resident, or nil"

  def portrait(assigns) do
    ~H"""
    <span data-portrait aria-hidden="true">
      <img :if={@url} src={@url} alt="" width="40" height="40" loading="lazy" decoding="async" />
      <span :if={is_nil(@url)}>{initial(@name)}</span>
    </span>
    """
  end

  defp initial(name) when is_binary(name), do: String.upcase(String.first(name) || "")
  defp initial(_no_name), do: nil

  @doc "The albums of a resident as links, the open one marked, with the form of a new album."
  attr :albums, :list, required: true
  attr :album, :any, required: true, doc: "the open album, or nil for all the photos"
  attr :counts, :map, required: true, doc: "the number of photos in each album, by its id"
  attr :total, :integer, required: true
  attr :path, :string, required: true
  attr :can_make?, :boolean, required: true

  def albums(assigns) do
    ~H"""
    <section aria-labelledby="albums-heading">
      <h2 id="albums-heading">Albums</h2>
      <nav aria-label="Albums">
        <ul>
          <li>
            <.link patch={@path} aria-current={if is_nil(@album), do: "page"}>
              All photos ({@total})
            </.link>
          </li>
          <li :for={album <- @albums}>
            <.link
              patch={"#{@path}?album=#{album.id}"}
              aria-current={if @album && @album.id == album.id, do: "page"}
            >
              {album.name} ({Map.get(@counts, album.id, 0)})
            </.link>
          </li>
        </ul>
      </nav>
      <p :if={@albums == []}>No album yet. An album keeps some of the photos together.</p>

      <details :if={@can_make?} id="make-album-details">
        <summary><.icon name="plus" /> Make an album</summary>
        <form id="make-album" phx-submit="make_album">
          <.input id="album-name" name="album[name]" label="Name of the album" value="" required />
          <footer><.button type="submit">Make the album</.button></footer>
        </form>
      </details>
    </section>
    """
  end

  @doc "The heading of an open album, with its new name and its removal."
  attr :album, :any, required: true
  attr :can_rename?, :boolean, required: true
  attr :can_remove?, :boolean, required: true

  def album_actions(assigns) do
    ~H"""
    <div data-album-actions>
      <details :if={@can_rename?} id="rename-album-details">
        <summary><.icon name="pencil" /> Rename the album</summary>
        <form id="rename-album" phx-submit="rename_album">
          <.input
            id="album-new-name"
            name="album[name]"
            label="New name of the album"
            value={@album.name}
            required
          />
          <footer><.button type="submit">Rename</.button></footer>
        </form>
      </details>
      <.confirm :if={@can_remove?} id="remove-album" summary="Remove the album">
        <p>Its photos stay.</p>
        <.button type="button" variant="danger" phx-click="remove_album">
          Remove the album {@album.name}
        </.button>
      </.confirm>
    </div>
    """
  end

  @doc """
  The form that adds photos: ten at most, each 20 MB at most, with a
  caption and a date for each of them. A new photo goes into the open
  album. The form says what was wrong with the photos that it sent, since
  the header of the page can be far above it.
  """
  attr :upload, :any, required: true
  attr :album, :any, required: true
  attr :max_date, :string, required: true
  attr :problems, :list, default: []

  def add_form(assigns) do
    ~H"""
    <details id="add-photos-details">
      <summary><.icon name="arrow-up-tray" /> Add photos</summary>
      <form id="add-photos" phx-submit="add" phx-change="choose">
        <.problems list={@problems} />
        <fieldset id="add-photos-files">
          <legend>Photos: JPEG, PNG, GIF or WebP, ten at most, each 20 MB at most</legend>
          <label for={@upload.ref}>Choose photos</label>
          <.live_file_input upload={@upload} />
          <.problems list={Enum.map(upload_errors(@upload), &upload_words/1)} />
          <ul :if={@upload.entries != []}>
            <li :for={entry <- @upload.entries} id={"new-photo-#{entry.ref}"}>
              {entry.client_name}
              <progress value={entry.progress} max="100" aria-label={"Sent of #{entry.client_name}"}>
                {entry.progress} percent
              </progress>
              <span :for={error <- upload_errors(@upload, entry)} role="alert">
                {UploadWords.of(error, entry, &upload_words/1)}
              </span>
              <.button
                type="button"
                phx-click="cancel_photo"
                phx-value-ref={entry.ref}
                aria-label={"Take out #{entry.client_name}"}
              >
                <.icon name="x-mark" /> Take out
              </.button>
            </li>
          </ul>
        </fieldset>
        <.input id="add-caption" name="add[caption]" label="Caption" value="" />
        <.input
          id="add-taken-on"
          name="add[taken_on]"
          type="date"
          label="Date"
          hint="Leave it empty for the date of the camera, or today."
          value=""
          max={@max_date}
        />
        <p :if={@album}>The photos go into the album {@album.name}.</p>
        <footer><.button type="submit">Add the photos</.button></footer>
      </form>
    </details>
    """
  end

  @doc "The words of a problem of a photo that the browser sends."
  def upload_words(:too_large), do: "The photo is more than 20 MB."
  def upload_words(:not_accepted), do: "Rescord takes a photo: JPEG, PNG, GIF or WebP."
  def upload_words(:too_many_files), do: "Choose ten photos at most."
  def upload_words(_other), do: "The photo did not arrive. Choose it again."

  @doc """
  The photos, as a grid of cards, the newest first. The card of the photo
  with the reference `problems_ref` says what its form refused.
  """
  attr :items, :list, required: true
  attr :albums, :list, required: true
  attr :profile_id, :any, required: true, doc: "the id of the photo that is the profile picture"
  attr :organisation, :any, required: true
  attr :resident, :any, required: true
  attr :role, :any, required: true
  attr :current_user, :any, required: true
  attr :can, :map, required: true
  attr :max_date, :string, required: true
  attr :problems, :list, default: []
  attr :problems_ref, :any, default: nil

  def grid(assigns) do
    ~H"""
    <p :if={@items == []} id="no-photos">No photo here yet.</p>
    <ul :if={@items != []} data-photos id="photos">
      <li :for={item <- @items} id={"item-#{ref(item)}"}>
        <.card
          item={item}
          albums={@albums}
          profile?={not is_nil(item.photo) and item.photo.id == @profile_id}
          organisation={@organisation}
          resident={@resident}
          role={@role}
          current_user={@current_user}
          can={@can}
          max_date={@max_date}
          problems={if ref(item) == @problems_ref, do: @problems, else: []}
        />
      </li>
    </ul>
    """
  end

  # A card is an article: the figure with the thumbnail and the words of the
  # photo, then its form, closed at first, then its buttons.
  attr :item, :map, required: true
  attr :albums, :list, required: true
  attr :profile?, :boolean, required: true
  attr :organisation, :any, required: true
  attr :resident, :any, required: true
  attr :role, :any, required: true
  attr :current_user, :any, required: true
  attr :can, :map, required: true
  attr :max_date, :string, required: true
  attr :problems, :list, default: []

  defp card(assigns) do
    assigns =
      assign(assigns,
        ref: ref(assigns.item),
        in_albums: in_albums(assigns),
        make_profile?: assigns.can.profile? and not assigns.profile?,
        remove?: removable?(assigns)
      )

    ~H"""
    <article>
      <figure>
        <a href={item_open_url(@organisation, @item)}>
          <img src={item_thumbnail_url(@organisation, @item)} alt={alt(@item, @resident)} />
        </a>
        <figcaption>
          <span :if={@item.caption}>{@item.caption}</span>
          <small>
            <time datetime={Date.to_iso8601(@item.taken_on)}>
              {ResidentWords.date(@item.taken_on)}
            </time>
          </small>
          <strong :if={@profile?}><.icon name="star" /> Profile picture</strong>
          <small :if={@in_albums != []}>In {Enum.join(@in_albums, ", ")}</small>
          <a :if={item_display?(@item)} href={item_photo_url(@organisation, @item)}>Full size</a>
          <.link
            :if={@item.entry_id}
            navigate={
              ~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/journal?#{[entry: @item.entry_id]}"
            }
          >
            From the journal
          </.link>
        </figcaption>
      </figure>

      <details :if={@can.keep?} id={"change-#{@ref}"}>
        <summary><.icon name="pencil" /> Change</summary>
        <form id={"keep-#{@ref}"} phx-submit="keep">
          <.problems list={@problems} />
          <input type="hidden" name="photo[ref]" value={@ref} />
          <.input id={"caption-#{@ref}"} name="photo[caption]" label="Caption" value={@item.caption} />
          <.input
            id={"taken-on-#{@ref}"}
            name="photo[taken_on]"
            type="date"
            label="Date"
            value={Date.to_iso8601(@item.taken_on)}
            max={@max_date}
            required
          />
          <fieldset :if={@albums != []} id={"albums-#{@ref}"}>
            <legend>Albums</legend>
            <input type="hidden" name="photo[album_ids][]" value="" />
            <label :for={album <- @albums} for={"album-#{@ref}-#{album.id}"}>
              <input
                type="checkbox"
                id={"album-#{@ref}-#{album.id}"}
                name="photo[album_ids][]"
                value={album.id}
                checked={album.id in @item.album_ids}
              />
              {album.name}
            </label>
          </fieldset>
          <footer><.button type="submit">Save</.button></footer>
        </form>
      </details>

      <footer :if={@make_profile?}>
        <.button type="button" phx-click="make_profile" phx-value-ref={@ref}>
          <.icon name="star" /> Make it the profile picture
        </.button>
      </footer>
      <.confirm
        :if={@remove?}
        id={"remove-photo-#{@ref}"}
        summary="Remove"
        label={"Remove the photo of #{photo_name(@item)}"}
      >
        <p>The photo leaves the resident and each album.</p>
        <.button type="button" variant="danger" phx-click="remove_photo" phx-value-ref={@ref}>
          Remove the photo of {photo_name(@item)}
        </.button>
      </.confirm>
    </article>
    """
  end

  # The page offers no removal of a photo of the journal: it leaves the
  # photos when somebody takes it off its entry.
  defp removable?(%{item: %{photo: %{} = photo, attachment: nil}} = assigns),
    do: Rescord.Photos.can_remove_photo?(assigns.role, assigns.current_user, photo)

  defp removable?(_assigns), do: false

  defp in_albums(%{item: item, albums: albums}) do
    for album <- albums, album.id in item.album_ids, do: album.name
  end

  @doc """
  The reference of an item, which a form and a button send: `photo-<id>`
  for a photo record, and `attachment-<id>` for a photo of a journal entry
  that is no record yet.
  """
  def ref(%{photo: %{id: id}}), do: "photo-#{id}"
  def ref(%{attachment: %{id: id}}), do: "attachment-#{id}"

  defp alt(item, resident) do
    item.caption || "A photo of #{name(resident)}, #{ResidentWords.date(item.taken_on)}"
  end

  defp name(resident), do: resident.name || "a resident with no name"

  # The words that tell one photo from the others: its caption, or its date.
  defp photo_name(%{caption: caption}) when is_binary(caption), do: caption
  defp photo_name(item), do: ResidentWords.date(item.taken_on)

  @doc "The link to a photo record."
  def photo_url(organisation, photo), do: ~p"/o/#{organisation.short_name}/photos/#{photo.id}"

  @doc """
  The link that opens a photo record: its display file (issue 34), or the
  photo when it has none.
  """
  def open_url(organisation, photo) do
    if photo.display_key,
      do: ~p"/o/#{organisation.short_name}/photos/#{photo.id}/display",
      else: photo_url(organisation, photo)
  end

  @doc "The link to the thumbnail of a photo record, or to the photo when it has none."
  def thumbnail_url(organisation, photo) do
    if photo.thumbnail_key,
      do: ~p"/o/#{organisation.short_name}/photos/#{photo.id}/thumbnail",
      else: photo_url(organisation, photo)
  end

  defp item_open_url(organisation, %{photo: %{} = photo}), do: open_url(organisation, photo)

  defp item_open_url(organisation, %{attachment: attachment}),
    do: JournalComponents.attachment_url(organisation, attachment)

  defp item_display?(%{photo: %{} = photo}), do: not is_nil(photo.display_key)
  defp item_display?(%{attachment: attachment}), do: not is_nil(attachment.display_key)

  defp item_photo_url(organisation, %{photo: %{} = photo}), do: photo_url(organisation, photo)

  defp item_photo_url(organisation, %{attachment: attachment}),
    do: ~p"/o/#{organisation.short_name}/attachments/#{attachment.id}"

  defp item_thumbnail_url(organisation, %{photo: %{} = photo}),
    do: thumbnail_url(organisation, photo)

  defp item_thumbnail_url(organisation, %{attachment: %{thumbnail_key: nil} = attachment}),
    do: ~p"/o/#{organisation.short_name}/attachments/#{attachment.id}"

  defp item_thumbnail_url(organisation, %{attachment: attachment}),
    do: ~p"/o/#{organisation.short_name}/attachments/#{attachment.id}/thumbnail"
end
