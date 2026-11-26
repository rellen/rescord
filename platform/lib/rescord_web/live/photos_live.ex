defmodule RescordWeb.PhotosLive do
  @moduledoc """
  The photos of one resident, at `/o/<short name>/residents/<id>/photos`,
  and one of its albums at `?album=<id>` (ADR 0055).

  The page shows the profile picture, the albums, and the photos as a grid,
  the newest first: the photos that the members added, and the photos of
  the journal entries of the resident, each with a link to its entry. A
  member adds photos, ten at a time, with a caption and a date for them.
  Each photo has a form for its caption, its date and its albums, a button
  that makes it the profile picture, and one that removes it. A photo of
  the journal leaves the photos when somebody takes it off its entry.

  The page reads only the fields that it knows from what the browser sends,
  finds each photo and album among those that it has, and makes no atom
  from it. The policy of each resource decides when an action runs.
  """

  use RescordWeb, :live_view

  import RescordWeb.PhotoComponents

  alias Rescord.{Accounts, Photos, Residents}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    with true <- is_binary(id),
         {:ok, %{} = resident} <- Residents.resident(id, [load: [:name]] ++ options(socket)) do
      role = socket.assigns.role

      {:ok,
       socket
       |> assign(
         resident: resident,
         page_title: "Photos of #{resident.name || "a resident with no name"}",
         problems: [],
         max_date: Date.to_iso8601(Accounts.today(socket.assigns.organisation)),
         can: %{
           add?: Photos.role_can?(role, :photo, :add),
           keep?: Photos.role_can?(role, :photo, :describe),
           profile?: Photos.role_can?(role, :profile, :choose),
           make_album?: Photos.role_can?(role, :album, :make),
           rename_album?: Photos.role_can?(role, :album, :rename),
           remove_album?: Photos.role_can?(role, :album, :remove)
         }
       )
       |> allow_photos()}
    else
      _no_resident ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such resident.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}
    end
  end

  # The photos that a person adds, ten at a time. Rescord reads the type of
  # each photo from its first bytes again (ADR 0055).
  defp allow_photos(%{assigns: %{can: %{add?: true}}} = socket) do
    allow_upload(socket, :photos,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: 10,
      max_file_size: Photos.max_photo_size()
    )
  end

  defp allow_photos(socket), do: socket

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign_photos() |> open_album(params["album"])}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp path(%Phoenix.LiveView.Socket{assigns: assigns}), do: path(assigns)

  defp path(%{organisation: organisation, resident: resident}),
    do: ~p"/o/#{organisation.short_name}/residents/#{resident.id}/photos"

  defp assign_photos(socket) do
    options = options(socket)
    id = socket.assigns.resident.id
    {:ok, items} = Photos.photos_of(id, options)
    {:ok, albums} = Photos.albums(id, options)
    {:ok, profile} = Photos.profile_photo(id, options)

    assign(socket,
      items: items,
      albums: albums,
      profile: profile,
      counts: items |> Enum.flat_map(& &1.album_ids) |> Enum.frequencies()
    )
  end

  # The open album: one of the albums of the resident, or none for all the
  # photos. An id that is not one of those opens all the photos.
  defp open_album(socket, id) do
    album = is_binary(id) && Enum.find(socket.assigns.albums, &(&1.id == id))
    album = album || nil

    shown =
      if album,
        do: Enum.filter(socket.assigns.items, &(album.id in &1.album_ids)),
        else: socket.assigns.items

    assign(socket, album: album, shown: shown)
  end

  @impl true
  def handle_event("choose", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_photo", %{"ref" => ref}, socket) when is_binary(ref) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("add", params, %{assigns: %{can: %{add?: true}}} = socket) do
    fields = if is_map(params["add"]), do: params["add"], else: %{}
    options = options(socket)

    results =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, _entry ->
        result =
          %{
            resident_id: socket.assigns.resident.id,
            caption: non_blank(fields["caption"]),
            taken_on: non_blank(fields["taken_on"]),
            content: File.read!(path)
          }
          |> Photos.add_photo(options)
          |> into_album(socket.assigns.album, options)

        {:ok, result}
      end)

    case Enum.flat_map(results, &problems_of/1) do
      [] when results == [] ->
        {:noreply, assign(socket, problems: ["Choose a photo to add"])}

      [] ->
        words = if length(results) == 1, do: "The photo is added.", else: "The photos are added."
        reopen(socket, words)

      problems ->
        # The photos that went in are on the page, and the problems say why the others did not.
        {:noreply, socket |> assign(problems: Enum.uniq(problems)) |> refresh()}
    end
  end

  def handle_event("keep", %{"photo" => %{"ref" => ref} = fields}, socket) when is_binary(ref) do
    with_item(socket, ref, fn item ->
      album_ids =
        case fields["album_ids"] do
          ids when is_list(ids) -> known_albums(socket, ids)
          _none -> item.album_ids
        end

      item
      |> Photos.keep(
        %{
          caption: non_blank(fields["caption"]),
          taken_on: non_blank(fields["taken_on"]),
          album_ids: album_ids
        },
        options(socket)
      )
      |> after_write(socket, "The photo is saved.")
    end)
  end

  def handle_event("make_profile", %{"ref" => ref}, socket) when is_binary(ref) do
    with_item(socket, ref, fn item ->
      options = options(socket)

      with {:ok, photo} <- Photos.record_of(item, options) do
        Photos.set_profile_photo(photo, options)
      end
      |> after_write(socket, "The profile picture is changed.")
    end)
  end

  def handle_event("remove_photo", %{"ref" => ref}, socket) when is_binary(ref) do
    with_item(socket, ref, fn
      %{photo: %{} = photo, attachment: nil} ->
        photo
        |> Photos.remove_photo(options(socket))
        |> after_write(socket, "The photo is removed.")

      _from_journal ->
        {:noreply, socket}
    end)
  end

  def handle_event("clear_profile", _params, socket) do
    socket.assigns.resident.id
    |> Photos.clear_profile_photo(options(socket))
    |> after_write(socket, "The resident has no profile picture.")
  end

  def handle_event("make_album", %{"album" => %{"name" => name}}, socket) when is_binary(name) do
    case Photos.make_album(
           %{resident_id: socket.assigns.resident.id, name: name},
           options(socket)
         ) do
      {:ok, album} ->
        {:noreply,
         socket
         |> put_flash(:info, "The album is made.")
         |> push_navigate(to: "#{path(socket)}?album=#{album.id}")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event("rename_album", %{"album" => %{"name" => name}}, socket)
      when is_binary(name) do
    case socket.assigns.album do
      nil ->
        {:noreply, socket}

      album ->
        case Photos.rename_album(album, name, options(socket)) do
          {:ok, album} ->
            {:noreply,
             socket
             |> put_flash(:info, "The album is renamed.")
             |> push_navigate(to: "#{path(socket)}?album=#{album.id}")}

          {:error, error} ->
            {:noreply, assign(socket, problems: Accounts.error_messages(error))}
        end
    end
  end

  def handle_event("remove_album", _params, socket) do
    case socket.assigns.album do
      nil ->
        {:noreply, socket}

      album ->
        album
        |> Photos.remove_album(options(socket))
        |> after_write(socket, "The album is removed.")
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Runs `fun` with the item of a reference, when the page has that item.
  defp with_item(socket, ref, fun) do
    case Enum.find(socket.assigns.items, &(ref(&1) == ref)) do
      nil -> {:noreply, socket}
      item -> fun.(item)
    end
  end

  # The albums of this resident among the ids that the browser sent.
  defp known_albums(socket, ids) do
    known = MapSet.new(socket.assigns.albums, & &1.id)
    ids |> Enum.filter(&MapSet.member?(known, &1)) |> Enum.uniq()
  end

  defp into_album({:ok, photo}, nil, _options), do: {:ok, photo}

  defp into_album({:ok, photo}, album, options) do
    case Photos.add_to_album(%{album_id: album.id, photo_id: photo.id}, options) do
      {:ok, _tie} -> {:ok, photo}
      {:error, error} -> {:error, error}
    end
  end

  defp into_album({:error, error}, _album, _options), do: {:error, error}

  defp problems_of({:ok, _photo}), do: []
  defp problems_of({:error, error}), do: Accounts.error_messages(error)

  defp refresh(socket) do
    album_id = socket.assigns.album && socket.assigns.album.id
    socket |> assign_photos() |> open_album(album_id)
  end

  # Opens the page again after a write, or shows what was wrong. A form that
  # stays on the page keeps what the person typed.
  defp after_write(result, socket, words) do
    case result do
      {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
      _done -> reopen(socket, words)
    end
  end

  defp reopen(socket, words) do
    query = if socket.assigns.album, do: "?album=#{socket.assigns.album.id}", else: ""

    {:noreply,
     socket
     |> put_flash(:info, words)
     |> push_navigate(to: path(socket) <> query)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/residents"}>Residents</.link>
        ›
        <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}"}>
          {@resident.name || "A resident with no name"}
        </.link>
      </nav>

      <.header>
        {@page_title}
        <:subtitle>
          {length(@items)} {if length(@items) == 1, do: "photo", else: "photos"}
        </:subtitle>
      </.header>

      <.problems list={@problems} />

      <.profile photo={@profile} organisation={@organisation} resident={@resident} />
      <.button
        :if={@profile && @can.profile?}
        type="button"
        phx-click="clear_profile"
        data-confirm="Leave the resident with no profile picture?"
      >
        No profile picture
      </.button>

      <.albums
        albums={@albums}
        album={@album}
        counts={@counts}
        total={length(@items)}
        path={path(assigns)}
        can_make?={@can.make_album?}
      />

      <section aria-labelledby="photos-heading">
        <h2 id="photos-heading">{if @album, do: @album.name, else: "All photos"}</h2>
        <.album_actions
          :if={@album}
          album={@album}
          can_rename?={@can.rename_album?}
          can_remove?={@can.remove_album?}
        />
        <.add_form
          :if={assigns[:uploads][:photos]}
          upload={assigns[:uploads][:photos]}
          album={@album}
          max_date={@max_date}
        />
        <.grid
          items={@shown}
          albums={@albums}
          profile_id={@profile && @profile.id}
          organisation={@organisation}
          resident={@resident}
          role={@role}
          current_user={@current_user}
          can={@can}
          max_date={@max_date}
        />
      </section>
    </Layouts.app>
    """
  end
end
