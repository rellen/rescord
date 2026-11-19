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
      <p :if={@partnerships == []}>This refuge has no partner yet.</p>
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
              <td>
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
                  Accept
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
                  Decline
                </.button>
                <.button
                  :if={@can_end? and partnership.state in [:asked, :accepted]}
                  phx-click="end"
                  phx-value-id={partnership.id}
                  aria-label={"End the partnership with #{Transfers.other(partnership, @organisation).name}"}
                >
                  End
                </.button>
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
          label="The short name of the refuge, from the address of its pages"
          value=""
          maxlength="40"
          required
        />
        <footer><.button type="submit">Ask the refuge</.button></footer>
      </form>
    </section>
    """
  end

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
              <td>{Transfers.other(transfer, @organisation).name}</td>
              <td>
                {TransferWords.time(DateTime.to_iso8601(transfer.sent_at), @organisation.time_zone)}
              </td>
              <td><.badge state={transfer.state} /></td>
              <td>
                <.button
                  :if={@can_answer? and transfer.state == :sent}
                  phx-click="accept"
                  phx-value-id={transfer.id}
                  aria-label={"Accept the transfer of #{transfer.resident_name}"}
                >
                  Accept
                </.button>
                <.button
                  :if={@can_answer? and transfer.state == :sent}
                  phx-click="decline"
                  phx-value-id={transfer.id}
                  aria-label={"Decline the transfer of #{transfer.resident_name}"}
                >
                  Decline
                </.button>
                <.button
                  :if={@can_withdraw? and transfer.state == :sent}
                  phx-click="withdraw"
                  phx-value-id={transfer.id}
                  aria-label={"Withdraw the transfer of #{transfer.resident_name}"}
                >
                  Withdraw
                </.button>
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
      <p :if={@partners == []}>
        This refuge has no partner yet. Ask a refuge on the page of the partner refuges first.
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
        zone: assigns.organisation.time_zone
      )

    ~H"""
    <.header>
      {@facts["name"] || "A resident with no name"}
      <:subtitle>
        A copy from {@transfer.from_organisation.name}, as it was on {TransferWords.time(
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
        <.fact term="Temperament" value={join(@facts["temperaments"])} />
        <.fact
          :for={identifier <- @facts["identifiers"] || []}
          term={identifier["kind"] || "Identifier"}
          value={identifier["value"]}
        />
        <.fact term="Arrived at the first refuge" value={TransferWords.date(@facts["arrived_on"])} />
        <.fact term="Status at the first refuge" value={TransferWords.value(@facts["status"])} />
      </dl>
    </section>

    <.entries id="copy-medical" title="Medical history" entries={@copy["medical"] || []} zone={@zone} />
    <.entries
      :if={@copy["journal"]}
      id="copy-journal"
      title="Other journal entries"
      entries={@copy["journal"]}
      zone={@zone}
    />

    <section :if={@copy["stay"]} aria-labelledby="copy-stay">
      <h2 id="copy-stay">Stay at the first refuge</h2>
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
      <h2 id="copy-placements">Placements at the first refuge</h2>
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

  # The journal entries of a copy, the newest first.
  def entries(assigns) do
    ~H"""
    <section aria-labelledby={@id}>
      <h2 id={@id}>{@title}</h2>
      <p :if={@entries == []}>The copy has no such entry.</p>
      <article :for={entry <- @entries}>
        <header>
          <strong>{TransferWords.value(entry["kind"])}</strong>
          <small>{TransferWords.time(entry["at"], @zone)}</small>
        </header>
        <p :if={TransferWords.facts(entry)}>{TransferWords.facts(entry)}</p>
        <p :if={entry["note"]}>{entry["note"]}</p>
      </article>
    </section>
    """
  end

  defp join(nil), do: nil
  defp join([]), do: nil
  defp join(list), do: Enum.join(list, ", ")
end
