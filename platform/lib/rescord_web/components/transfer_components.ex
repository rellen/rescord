defmodule RescordWeb.TransferComponents do
  @moduledoc """
  The parts of the pages of the partners and the transfers (ADR 0037 and
  ADR 0042): the partnerships, the question to a refuge, the lists of the
  transfers, the form that sends a resident, and the copy of a resident.
  """

  use RescordWeb, :html

  alias Rescord.Transfers
  alias RescordWeb.TransferWords

  @doc "The partnerships of the organisation, with what the reader can do with each."
  attr :partnerships, :list, required: true
  attr :organisation, :map, required: true
  attr :can_answer?, :boolean, required: true
  attr :can_end?, :boolean, required: true

  def partnerships(assigns) do
    ~H"""
    <section aria-labelledby="partners-heading">
      <h2 id="partners-heading">Partnerships</h2>
      <p :if={@partnerships == []}>There is no partner refuge yet.</p>
      <div :if={@partnerships != []} data-scroll>
        <table>
          <thead>
            <tr>
              <th scope="col">Refuge</th>
              <th scope="col">Who asked</th>
              <th scope="col">State</th>
              <th scope="col">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={partnership <- @partnerships} id={"partnership-#{partnership.id}"}>
              <td>{Transfers.other(partnership, @organisation).name}</td>
              <td data-label="Who asked">
                {if partnership.from_organisation_id == @organisation.id,
                  do: "This refuge",
                  else: "That refuge"}
              </td>
              <td><.badge state={partnership.state} /></td>
              <td>
                <.button
                  :if={
                    @can_answer? and partnership.state == :asked and
                      partnership.to_organisation_id == @organisation.id
                  }
                  phx-click="accept"
                  phx-value-id={partnership.id}
                  aria-label={"Accept #{Transfers.other(partnership, @organisation).name} as a partner"}
                >
                  <.icon name="check" /> Accept
                </.button>
                <.button
                  :if={
                    @can_answer? and partnership.state == :asked and
                      partnership.to_organisation_id == @organisation.id
                  }
                  phx-click="decline"
                  phx-value-id={partnership.id}
                  aria-label={"Decline #{Transfers.other(partnership, @organisation).name} as a partner"}
                >
                  <.icon name="x-circle" /> Decline
                </.button>
                <.confirm
                  :if={@can_end? and partnership.state in [:asked, :accepted]}
                  id={"end-#{partnership.id}"}
                  summary="End"
                  label={"End the partnership with #{Transfers.other(partnership, @organisation).name}"}
                  icon="no-symbol"
                >
                  <p>No transfer goes either way after this. The transfers before it stay.</p>
                  <.button variant="danger" phx-click="end" phx-value-id={partnership.id}>
                    End the partnership with {Transfers.other(partnership, @organisation).name}
                  </.button>
                </.confirm>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  @doc "The form that asks a refuge, by its short name, to be a partner."
  def ask_form(assigns) do
    ~H"""
    <section aria-labelledby="ask-heading">
      <h2 id="ask-heading">Ask a refuge</h2>
      <form id="ask" phx-submit="ask">
        <.input
          id="ask-short-name"
          name="partner[short_name]"
          type="text"
          label="Short name of the refuge"
          hint="Ask the refuge for it: it is the word after /o/ in the address of its pages. The refuge becomes a partner when it accepts."
          value=""
          maxlength="40"
          autocapitalize="none"
          spellcheck="false"
          required
        />
        <footer><.button type="submit">Ask the refuge</.button></footer>
      </form>
    </section>
    """
  end

  @doc """
  The partners on other servers (ADR 0043): each with its fingerprint, the
  card of this refuge to give them, and the form that records a card.
  """
  attr :remote, :list, required: true
  attr :card, :any, required: true
  attr :fingerprint, :any, required: true
  attr :can_record?, :boolean, required: true
  attr :can_end?, :boolean, required: true

  def remote_partners(assigns) do
    ~H"""
    <section aria-labelledby="remote-heading">
      <h2 id="remote-heading">Refuges on other servers</h2>
      <p>
        A refuge that signs in at the same address as you is on this server, and becomes a
        partner when you ask it. A refuge that uses Rescord at another address is on another
        server: you swap partner cards with it.
      </p>
      <p :if={@remote == []}>There is no partner refuge on another server yet.</p>
      <div :if={@remote != []} data-scroll>
        <table>
          <thead>
            <tr>
              <th scope="col">Refuge</th>
              <th scope="col">Fingerprint</th>
              <th scope="col">State</th>
              <th scope="col">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={partner <- @remote} id={"remote-#{partner.id}"}>
              <td>{partner.name}</td>
              <td data-label="Fingerprint"><code>{partner.fingerprint}</code></td>
              <td><.badge state={partner.state} /></td>
              <td>
                <.confirm
                  :if={@can_end? and partner.state == :active}
                  id={"end-remote-#{partner.id}"}
                  summary="End"
                  label={"End the partnership with #{partner.name}"}
                  icon="no-symbol"
                >
                  <p>No transfer goes either way after this. The transfers before it stay.</p>
                  <.button variant="danger" phx-click="end_remote" phx-value-id={partner.id}>
                    End the partnership with {partner.name}
                  </.button>
                </.confirm>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@can_record?}>
        <h3>The partner card of this refuge</h3>
        <p>
          Give this card to the refuge on the other server, by email or on paper. It holds no
          secret. Before the first file, read the fingerprint (the letters and numbers below) to
          each other by phone or in person. If the two are not the same, do not use the card.
        </p>
        <.input
          id="own-card"
          name="own_card"
          type="textarea"
          label="Partner card"
          value={@card}
          readonly
        />
        <p>Fingerprint: <code id="own-fingerprint">{@fingerprint}</code></p>

        <form id="record" phx-submit="record">
          <.input
            id="record-card"
            name="remote[card]"
            type="textarea"
            label="The partner card of the other refuge"
            hint="Paste the text that the other refuge gave you."
            value=""
            maxlength="2000"
            required
          />
          <footer><.button type="submit">Record the partner</.button></footer>
        </form>
      </div>
    </section>
    """
  end

  @doc """
  The form that writes a transfer file for a partner on another server. It
  posts to `RescordWeb.TransferFileController`, which sends the file.
  """
  attr :organisation, :map, required: true
  attr :remote, :list, required: true
  attr :residents, :list, required: true
  attr :parts, :list, required: true

  def export_form(assigns) do
    ~H"""
    <section aria-labelledby="export-heading">
      <h2 id="export-heading">Send a resident to a refuge on another server</h2>
      <p>
        Rescord makes a transfer file. Give it to the partner refuge, by email or on a USB stick,
        and it adds the file on its page of the transfers.
      </p>
      <p :if={@remote == []}>
        There is no partner refuge on another server yet. Record one on
        <.link navigate={~p"/o/#{@organisation.short_name}/partners"}>the page of the partner refuges</.link>
        first.
      </p>
      <.form
        :if={@remote != []}
        for={%{}}
        as={:export}
        id="export"
        action={~p"/o/#{@organisation.short_name}/transfers/export"}
        method="post"
      >
        <.input
          id="export-resident"
          name="export[resident_id]"
          type="select"
          label="Resident"
          prompt="Choose"
          options={@residents}
          value=""
          required
        />
        <.input
          id="export-partner"
          name="export[remote_partner_id]"
          type="select"
          label="Partner on another server"
          prompt="Choose"
          options={@remote}
          value=""
          required
        />
        <fieldset id="export-parts">
          <legend>
            What the file holds: the facts and the medical history always, with the photos and
            PDFs of their entries, and the parts that you tick
          </legend>
          <label :for={{part, words} <- TransferWords.parts()}>
            <input type="checkbox" name="export[parts][]" value={part} checked={part in @parts} />
            {words}
          </label>
        </fieldset>
        <.input
          id="export-note"
          name="export[note]"
          type="textarea"
          label="Note to the refuge"
          value=""
          maxlength="2000"
        />
        <footer>
          <.button type="submit"><.icon name="arrow-down-tray" /> Write the transfer file</.button>
        </footer>
      </.form>
    </section>
    """
  end

  @doc "The form that imports a transfer file from a partner on another server."
  attr :upload, :any, required: true

  def import_form(assigns) do
    ~H"""
    <section aria-labelledby="import-heading">
      <h2 id="import-heading">Import a transfer file</h2>
      <p>
        Did a partner refuge on another server give you a transfer file? Its name ends in <code>.rescord</code>. Add it here, and it waits under Received for you to accept or
        decline.
      </p>
      <form id="import" phx-submit="import" phx-change="choose_file">
        <label for={@upload.ref}>Transfer file</label>
        <.live_file_input upload={@upload} />
        <.problems list={Enum.map(upload_errors(@upload), &import_words/1)} />
        <p :for={entry <- @upload.entries} id={"import-#{entry.ref}"}>
          {entry.client_name}
          <span :for={error <- upload_errors(@upload, entry)} role="alert">{import_words(error)}</span>
        </p>
        <footer>
          <.button type="submit"><.icon name="arrow-up-tray" /> Import the file</.button>
        </footer>
      </form>
    </section>
    """
  end

  @doc "The words of a problem of a transfer file that the browser sends."
  def import_words(:too_large), do: "The file is larger than Rescord takes."

  def import_words(:not_accepted),
    do: "Choose a transfer file of Rescord: its name ends in .rescord."

  def import_words(:too_many_files), do: "Choose one file."
  def import_words(_other), do: "The file did not arrive. Choose it again."

  attr :state, :atom, required: true

  # The state of a partnership or a transfer, as a badge.
  def badge(assigns) do
    assigns = assign(assigns, words: TransferWords.state(assigns.state))

    ~H"""
    <.state kind={elem(@words, 1)}>{elem(@words, 0)}</.state>
    """
  end

  @doc "The transfers that the organisation received, or sent."
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :empty, :string, required: true
  attr :transfers, :list, required: true
  attr :organisation, :map, required: true
  attr :can_answer?, :boolean, required: true
  attr :can_withdraw?, :boolean, required: true
  attr :can_send_again?, :boolean, default: false

  def transfers_table(assigns) do
    ~H"""
    <section aria-labelledby={"#{@id}-heading"} id={@id}>
      <h2 id={"#{@id}-heading"}>{@title}</h2>
      <p :if={@transfers == []}>{@empty}</p>
      <div :if={@transfers != []} data-scroll>
        <table>
          <thead>
            <tr>
              <th scope="col">Resident</th>
              <th scope="col">Refuge</th>
              <th scope="col">Sent</th>
              <th scope="col">State</th>
              <th scope="col">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={transfer <- @transfers} id={"transfer-#{transfer.id}"}>
              <td>
                <.link
                  :if={
                    transfer.state == :accepted or transfer.from_organisation_id == @organisation.id
                  }
                  navigate={~p"/o/#{@organisation.short_name}/transfers/#{transfer.id}"}
                >
                  {transfer.resident_name || "A resident with no name"}
                </.link>
                <span :if={
                  transfer.state != :accepted and transfer.from_organisation_id != @organisation.id
                }>
                  {transfer.resident_name || "A resident with no name"}
                </span>
                <small :if={transfer.note}>{transfer.note}</small>
              </td>
              <td data-label="Refuge">{Transfers.other(transfer, @organisation).name}</td>
              <td data-label="Sent">
                {TransferWords.time(DateTime.to_iso8601(transfer.sent_at), @organisation.time_zone)}
              </td>
              <td data-label="State">
                <.badge state={transfer.state} />
                <small :if={transfer.state == :sending}>{TransferWords.files_copied(transfer)}</small>
                <small :if={transfer.state == :failed}>{TransferWords.failure(transfer.failure)}</small>
              </td>
              <td>
                <.button
                  :if={@can_answer? and transfer.state == :sent}
                  phx-click="accept"
                  phx-value-id={transfer.id}
                  aria-label={"Accept the transfer of #{transfer.resident_name}"}
                >
                  <.icon name="check" /> Accept
                </.button>
                <.button
                  :if={@can_answer? and transfer.state == :sent}
                  phx-click="decline"
                  phx-value-id={transfer.id}
                  aria-label={"Decline the transfer of #{transfer.resident_name}"}
                >
                  <.icon name="x-circle" /> Decline
                </.button>
                <.button
                  :if={@can_send_again? and transfer.state == :failed}
                  phx-click="send_again"
                  phx-value-id={transfer.id}
                  aria-label={"Send the transfer of #{transfer.resident_name} again"}
                >
                  Send again
                </.button>
                <.confirm
                  :if={@can_withdraw? and transfer.state in [:sending, :sent, :failed]}
                  id={"withdraw-#{transfer.id}"}
                  summary="Withdraw"
                  label={"Withdraw the transfer of #{transfer.resident_name}"}
                  icon="arrow-uturn-left"
                >
                  <p>
                    The transfer is taken back before an answer. The partner refuge cannot accept it.
                  </p>
                  <.button variant="danger" phx-click="withdraw" phx-value-id={transfer.id}>
                    Withdraw the transfer of {transfer.resident_name}
                  </.button>
                </.confirm>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  @doc "The form that sends a copy of a resident to a partner refuge."
  attr :form, :any, required: true
  attr :partners, :list, required: true
  attr :residents, :list, required: true

  def send_form(assigns) do
    assigns = assign(assigns, chosen: List.wrap(assigns.form[:parts].value))

    ~H"""
    <section aria-labelledby="send-heading">
      <h2 id="send-heading">Send a resident</h2>
      <p>
        This sends a copy of the record of the resident to a partner refuge. The resident stays
        on your list: record its departure yourself. The partner reads the copy once it accepts,
        and the copy does not add the resident to its list.
      </p>
      <p :if={@partners == []}>
        There is no partner refuge yet. Ask a refuge on the page of the partner refuges first.
      </p>
      <.form :if={@partners != []} for={@form} id="send" phx-submit="send">
        <.input
          field={@form[:resident_id]}
          type="select"
          label="Resident"
          prompt="Choose"
          options={@residents}
          required
        />
        <.input
          field={@form[:partner_id]}
          type="select"
          label="Partner refuge"
          prompt="Choose"
          options={@partners}
          required
        />
        <fieldset id="send-parts">
          <legend>
            What the copy holds: the facts and the medical history always, and the parts that you tick
          </legend>
          <label :for={{part, words} <- TransferWords.parts()}>
            <input
              type="checkbox"
              name="transfer[parts][]"
              value={part}
              checked={Atom.to_string(part) in @chosen}
            />
            {words}
          </label>
        </fieldset>
        <.input field={@form[:note]} type="textarea" label="Note to the refuge" maxlength="2000" />
        <footer><.button type="submit">Send the copy</.button></footer>
      </.form>
    </section>
    """
  end

  @doc "The copy of a resident that a transfer holds. It does not change."
  attr :transfer, :map, required: true
  attr :organisation, :map, required: true

  def copy(assigns) do
    assigns =
      assign(assigns,
        copy: assigns.transfer.snapshot,
        facts: assigns.transfer.snapshot["facts"] || %{},
        zone: assigns.organisation.time_zone,
        sender: (assigns.transfer.from_organisation || assigns.transfer.remote_partner).name
      )

    ~H"""
    <.header icon={Icons.section(:transfers)}>
      <:crumb navigate={~p"/o/#{@organisation.short_name}"}>{@organisation.name}</:crumb>
      <:crumb navigate={~p"/o/#{@organisation.short_name}/transfers"}>Transfers</:crumb>
      {@facts["name"] || "A resident with no name"}
      <:subtitle>
        A copy from {Transfers.other(@transfer, @organisation).name}, as it was on {TransferWords.time(
          @copy["taken_at"],
          @zone
        )}. It does not change.
      </:subtitle>
    </.header>

    <p :if={@transfer.note}>Note: {@transfer.note}</p>

    <section aria-labelledby="copy-facts">
      <h2 id="copy-facts">Facts</h2>
      <dl>
        <.fact term="Species" value={@facts["species"]} />
        <.fact term="Sex" value={TransferWords.value(@facts["sex"])} />
        <.fact
          term="Born"
          value={
            TransferWords.date(@facts["born_on"]) &&
              "#{TransferWords.date(@facts["born_on"])}#{if @facts["born_on_estimated"], do: ", estimated"}"
          }
        />
        <.fact term="Desexed" value={TransferWords.value(@facts["desex_status"])} />
        <.fact term="Breeds" value={join(@facts["breeds"])} />
        <.fact term="Colours" value={join(@facts["colours"])} />
        <.fact term="Size" value={@facts["size_class"]} />
        <.fact term="Coat" value={@facts["coat"]} />
        <.fact term="Markings" value={@facts["markings"]} />
        <.fact term="Temperament" value={join(@facts["temperaments"])} />
        <.fact
          :for={identifier <- @facts["identifiers"] || []}
          term={identifier["kind"] || "Identifier"}
          value={identifier["value"]}
        />
        <.fact term={"Arrived at #{@sender}"} value={TransferWords.date(@facts["arrived_on"])} />
        <.fact term={"Status at #{@sender}"} value={TransferWords.value(@facts["status"])} />
      </dl>
    </section>

    <.photos
      :if={@copy["photos"]}
      part={@copy["photos"]}
      name={@facts["name"]}
      file_path={file_path(@transfer, @organisation)}
    />

    <section :if={is_list(@copy["conditions"])} aria-labelledby="copy-conditions">
      <h2 id="copy-conditions">Conditions</h2>
      <p :if={@copy["conditions"] == []}>The copy has no condition.</p>
      <ul :if={@copy["conditions"] != []} data-conditions>
        <li :for={condition <- @copy["conditions"]}>
          <strong>{condition["condition"]}</strong>
          <.copy_condition_state condition={condition} />
          <small>{TransferWords.condition(condition)}</small>
        </li>
      </ul>
    </section>

    <.entries
      id="copy-medical"
      title="Medical history"
      entries={@copy["medical"] || []}
      zone={@zone}
      file_path={file_path(@transfer, @organisation)}
    />
    <.entries
      :if={@copy["journal"]}
      id="copy-journal"
      title="Other journal entries"
      entries={@copy["journal"]}
      zone={@zone}
      file_path={file_path(@transfer, @organisation)}
    />

    <section :if={@copy["stay"]} aria-labelledby="copy-stay">
      <h2 id="copy-stay">Stay at {@sender}</h2>
      <dl>
        <.fact
          term="Arrival"
          value={
            @copy["stay"]["arrival"] &&
              "#{TransferWords.date(@copy["stay"]["arrival"]["on"])}, #{TransferWords.value(@copy["stay"]["arrival"]["kind"])}"
          }
        />
        <.fact
          term="Away"
          value={@copy["stay"]["absence"] && @copy["stay"]["absence"]["reason"]}
        />
        <.fact
          term="Departure"
          value={
            @copy["stay"]["departure"] &&
              "#{TransferWords.date(@copy["stay"]["departure"]["on"])}, #{TransferWords.value(@copy["stay"]["departure"]["kind"])}"
          }
        />
      </dl>
    </section>

    <section :if={@copy["placements"]} aria-labelledby="copy-placements">
      <h2 id="copy-placements">Placements at {@sender}</h2>
      <p :if={@copy["placements"] == []}>No placement is recorded.</p>
      <ul :if={@copy["placements"] != []}>
        <li :for={placement <- @copy["placements"]}>
          {TransferWords.time(placement["at"], @zone)}: {TransferWords.value(placement["kind"])}, {placement[
            "location"
          ]}
        </li>
      </ul>
    </section>

    <section :if={@copy["relations"]} aria-labelledby="copy-relations">
      <h2 id="copy-relations">Families and groups</h2>
      <dl>
        <.fact
          :for={parent <- @copy["relations"]["parents"] || []}
          term={TransferWords.value(parent["role"])}
          value={parent["name"]}
        />
        <.fact term="Young" value={join(@copy["relations"]["young"])} />
        <.fact term="Families" value={join(@copy["relations"]["families"])} />
        <.fact term="Groups" value={join(@copy["relations"]["groups"])} />
      </dl>
    </section>
    """
  end

  attr :condition, :map, required: true

  # The state of a condition of the copy: a shape and a word.
  defp copy_condition_state(assigns) do
    {kind, word} = TransferWords.condition_state(assigns.condition)
    assigns = assign(assigns, kind: kind, word: word)

    ~H"""
    <.state kind={@kind}>{@word}</.state>
    """
  end

  attr :term, :string, required: true
  attr :value, :any, required: true
  attr :rest, :global

  # One fact of the copy, when the copy has it.
  def fact(assigns) do
    ~H"""
    <div :if={@value not in [nil, ""]}>
      <dt>{@term}</dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :entries, :list, required: true
  attr :zone, :string, required: true
  attr :file_path, :any, required: true, doc: "the path of a file of the copy, or nil"

  # The journal entries of a copy, the newest first, each with its files.
  def entries(assigns) do
    ~H"""
    <section aria-labelledby={@id}>
      <h2 id={@id}>{@title}</h2>
      <p :if={@entries == []}>The copy has no such entry.</p>
      <article :for={entry <- @entries}>
        <header>
          <strong>
            <.icon :if={Icons.entry_kind(entry["kind"])} name={Icons.entry_kind(entry["kind"])} />
            {TransferWords.value(entry["kind"])}
          </strong>
          <small>{TransferWords.time(entry["at"], @zone)}</small>
        </header>
        <p :if={entry["about"]} data-about>About {entry["about"]}</p>
        <p :if={TransferWords.facts(entry)}>{TransferWords.facts(entry)}</p>
        <p :if={entry["note"]}>{entry["note"]}</p>
        <ul :if={(entry["files"] || []) != []} aria-label="Files of the entry">
          <li :for={file <- entry["files"]}>
            <a :if={@file_path} href={@file_path.(file["id"])}>{file["name"]}</a>
            <span :if={is_nil(@file_path)}>{file["name"]}</span>
            <small :if={is_integer(file["size"])}>{RescordWeb.JournalWords.file_size(file["size"])}</small>
          </li>
        </ul>
      </article>
    </section>
    """
  end

  attr :part, :map, required: true, doc: "the part of the copy with the photos"
  attr :name, :any, required: true, doc: "the name of the resident, or nil"
  attr :file_path, :any, required: true, doc: "the path of a file of the copy, or nil"

  # The photos of a copy (ADR 0057), the newest first, with the profile
  # picture and the albums. The copy of an export has no file on this
  # server, so it shows the words of each photo alone.
  def photos(assigns) do
    albums = for %{"name" => _name} = album <- List.wrap(assigns.part["albums"]), do: album
    profile = assigns.part["profile"]

    cards =
      for %{"id" => id} = photo <- List.wrap(assigns.part["photos"]) do
        %{
          id: id,
          href: assigns.file_path && assigns.file_path.(id),
          src: assigns.file_path && assigns.file_path.(thumbnail_id(photo)),
          alt: photo_alt(photo, assigns.name),
          caption: photo["caption"],
          taken_on: photo["taken_on"],
          date: TransferWords.date(photo["taken_on"]),
          profile?: is_binary(profile) and profile == id,
          albums:
            for(album <- albums, id in List.wrap(album["photos"]), do: album["name"])
            |> Enum.join(", ")
        }
      end

    assigns =
      assign(assigns,
        cards: cards,
        albums: albums,
        profile: Enum.find(cards, &(&1.profile? and &1.src))
      )

    ~H"""
    <section aria-labelledby="copy-photos">
      <h2 id="copy-photos">Photos</h2>
      <p :if={@cards == []}>The copy has no photo.</p>
      <figure :if={@profile} data-profile id="copy-profile-photo">
        <a href={@profile.href}><img src={@profile.src} alt={@profile.alt} /></a>
        <figcaption>Profile picture</figcaption>
      </figure>
      <ul :if={@cards != []} data-photos id="copy-photo-list">
        <li :for={card <- @cards} id={"copy-photo-#{card.id}"}>
          <figure>
            <a :if={card.src} href={card.href}>
              <img src={card.src} alt={card.alt} loading="lazy" />
            </a>
            <figcaption>
              <span :if={card.caption}>{card.caption}</span>
              <small :if={card.date}><time datetime={card.taken_on}>{card.date}</time></small>
              <strong :if={card.profile?}><.icon name="star" /> Profile picture</strong>
              <small :if={card.albums != ""}>In {card.albums}</small>
            </figcaption>
          </figure>
        </li>
      </ul>
      <h3 :if={@albums != []} id="copy-albums">Albums</h3>
      <ul :if={@albums != []} aria-labelledby="copy-albums">
        <li :for={album <- @albums}>
          {album["name"]}: {album_size(album)}
        </li>
      </ul>
    </section>
    """
  end

  # The file that shows a photo in the grid: its thumbnail, or the photo
  # itself for an old photo of the journal that has none.
  defp thumbnail_id(%{"thumbnail" => %{"id" => id}}), do: id
  defp thumbnail_id(%{"id" => id}), do: id

  defp photo_alt(%{"caption" => caption}, _name) when is_binary(caption), do: caption

  defp photo_alt(photo, name) do
    ["A photo of #{name || "a resident with no name"}", TransferWords.date(photo["taken_on"])]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp album_size(album) do
    case length(List.wrap(album["photos"])) do
      1 -> "1 photo"
      count -> "#{count} photos"
    end
  end

  # The path of a file of the copy. A file exported to another server is
  # not kept on this one, so its copy has no link. While a job copies the
  # files, and after it stopped, a transfer has sources, and some of its
  # files are not there yet (ADR 0100).
  defp file_path(%{to_organisation_id: nil}, _organisation), do: nil
  defp file_path(%{sources: [_ | _]}, _organisation), do: nil

  defp file_path(transfer, organisation),
    do: &~p"/o/#{organisation.short_name}/transfers/#{transfer.id}/files/#{&1}"

  defp join(nil), do: nil
  defp join([]), do: nil
  defp join(list), do: Enum.join(list, ", ")
end
