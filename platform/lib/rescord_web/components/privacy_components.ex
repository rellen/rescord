defmodule RescordWeb.PrivacyComponents do
  @moduledoc """
  The parts of the pages of privacy (ADR 0105): the requests to erase data
  of an organisation, the form of a request that came another way, the
  settings of privacy, and what an erasure does, on the page of a request.
  """

  use RescordWeb, :html

  alias Rescord.Accounts
  alias RescordWeb.{PrivacyWords, ResidentWords}

  attr :id, :string, required: true
  attr :requests, :list, required: true
  attr :people, :map, required: true, doc: "the labels of `Rescord.Accounts.labels/1`"
  attr :organisation, :map, required: true
  attr :today, Date, required: true
  attr :empty, :string, required: true

  @doc "A list of requests, each with its person, its days and a link to its page."
  def requests(assigns) do
    ~H"""
    <p :if={@requests == []}>{@empty}</p>
    <table :if={@requests != []} id={@id}>
      <thead>
        <tr>
          <th scope="col">Whose data</th>
          <th scope="col">Received</th>
          <th scope="col">How</th>
          <th scope="col">State</th>
          <th scope="col">Due</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={request <- @requests} id={"request-#{request.id}"}>
          <td data-label="Whose data">
            <.link navigate={~p"/o/#{@organisation.short_name}/privacy/#{request.id}"}>
              {person(@people, request)}
            </.link>
          </td>
          <td data-label="Received">{ResidentWords.date(request.received_on)}</td>
          <td data-label="How">{PrivacyWords.how(request.how_received)}</td>
          <td data-label="State">
            <.state kind={PrivacyWords.state(request.state) |> elem(1)}>
              {PrivacyWords.state(request.state) |> elem(0)}
            </.state>
          </td>
          <td data-label="Due">
            <span :if={request.state == :received}>
              {ResidentWords.date(due(request))}, {PrivacyWords.days_left(
                Date.diff(due(request), @today)
              )}
            </span>
            <span :if={request.state != :received}>Closed</span>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc "The person of a request: their label, or Former member N after the erasure."
  @spec person(map, map) :: String.t()
  def person(_people, %{former_number: number}) when is_integer(number),
    do: "Former member #{number}"

  def person(people, request),
    do: Map.get(people, request.user_id, "A former member")

  @doc "The day that a request is due, after any extension."
  @spec due(map) :: Date.t()
  def due(request), do: request.extended_to || request.due_on

  attr :form, :any, required: true

  attr :choices, :list,
    required: true,
    doc: "each member and former member as `{label, member id}`"

  @doc "The form of a request that came by email, by letter or in person."
  def record_form(assigns) do
    ~H"""
    <section id="record-request" aria-labelledby="record-heading">
      <h2 id="record-heading">Record a request</h2>
      <p>
        A person asked by email, by letter or in person to erase their data. Record it here
        first: the request says when it came, and when it is due, one calendar month later.
      </p>
      <.form for={@form} id="record" phx-submit="record">
        <.input
          field={@form[:member_id]}
          type="select"
          label="Whose data"
          prompt="Choose the person"
          options={@choices}
          required
        />
        <.input
          field={@form[:how_received]}
          type="select"
          label="How it came"
          options={PrivacyWords.way_options()}
          required
        />
        <.input
          field={@form[:identity]}
          type="text"
          label="How you checked who asked"
          maxlength="300"
          required
        />
        <.input field={@form[:received_on]} type="date" label="The day it came" required />
        <.input
          field={@form[:identity_confirmed_on]}
          type="date"
          label="The day you confirmed who asked, when that was later"
        />
        <.input
          field={@form[:contact]}
          type="text"
          label="How to answer the person, when not the email of their account"
          maxlength="500"
        />
        <footer><.button type="submit">Record the request</.button></footer>
      </.form>
    </section>
    """
  end

  attr :form, :any, required: true
  attr :can_change?, :boolean, required: true
  attr :settings, :map, required: true

  @doc "The settings of privacy: how long what stays, and the blanks of the notice."
  def settings(assigns) do
    ~H"""
    <section id="privacy-settings" aria-labelledby="privacy-settings-heading">
      <h2 id="privacy-settings-heading">Settings of privacy</h2>
      <dl :if={not @can_change?}>
        <dt>Money records keep the email of an erased person for</dt>
        <dd>{@settings.money_years} years</dd>
        <dt>A former member is pseudonymised after</dt>
        <dd>{months(@settings.pseudonymise_after_months)}</dd>
        <dt>A closed request stays for</dt>
        <dd>{@settings.closed_request_years} years</dd>
      </dl>
      <.form :if={@can_change?} for={@form} id="settings" phx-submit="save_settings">
        <.input
          field={@form[:money_years]}
          type="number"
          label="Years that the money records keep the email of an erased person"
          min="1"
          max="30"
          required
        />
        <p>
          As general information, and not legal advice: in Australia, tax records stay 5 years,
          and the records of a charity of the ACNC 7 years. Ask somebody who knows the law of
          your organisation.
        </p>
        <.input
          field={@form[:pseudonymise_after_months]}
          type="number"
          label="Months after which a former member is pseudonymised with no request (empty: never)"
          min="1"
          max="600"
        />
        <.input
          field={@form[:closed_request_years]}
          type="number"
          label="Years that a closed request stays, as the proof of what was done"
          min="1"
          max="30"
          required
        />
        <.input
          field={@form[:contact_name]}
          type="text"
          label="Who answers about privacy"
          maxlength="120"
        />
        <.input
          field={@form[:contact_email]}
          type="email"
          label="Where a person writes about privacy"
          maxlength="254"
        />
        <.input
          field={@form[:authority]}
          type="text"
          label="The authority that a person can complain to"
          maxlength="200"
        />
        <.input
          field={@form[:notice_text]}
          type="textarea"
          label="Words of your own at the end of the privacy notice"
          maxlength="5000"
        />
        <footer><.button type="submit">Save the settings</.button></footer>
      </.form>
    </section>
    """
  end

  defp months(nil), do: "never"
  defp months(1), do: "1 month"
  defp months(months), do: "#{months} months"

  attr :hold_until, :any,
    required: true,
    doc: "the day of the hold of the money records, or `nil`"

  attr :form, :any, required: true
  attr :organisation, :map, required: true

  @doc "What an erasure does and does not do, and its form."
  def erasure(assigns) do
    ~H"""
    <section id="erasure" aria-labelledby="erasure-heading">
      <h2 id="erasure-heading">Erase</h2>
      <h3>What goes</h3>
      <ul>
        <li>The email address on each record of {@organisation.name}: each page names the person
          "Former member" and a number.</li>
        <li>Their place as a member, if they are one, their tasks that are due, their routines
          and their calendar feeds.</li>
        <li>Their conversations with Ruby, their notifications, and what they follow.</li>
        <li>Their account, when they are a member of no other organisation on this server.</li>
      </ul>
      <h3>What stays, with no name</h3>
      <ul>
        <li>The records that they wrote about the animals: the journal, the tasks, the stock.
          The care of each animal depends on them.</li>
        <li :if={@hold_until}>
          The money records keep their email until {ResidentWords.date(@hold_until)}, because
          the law asks for them. Only the pages of the expenses show it.
        </li>
        <li :if={is_nil(@hold_until)}>No money record needs their email.</li>
      </ul>
      <h3>What Rescord cannot reach</h3>
      <ul>
        <li>Words that members typed about the person in a record, and the old words in its
          history.</li>
        <li>Emails that Rescord sent, files that somebody downloaded, and a copy of a transfer at
          a partner refuge. Tell a partner if you sent them more.</li>
        <li>The backups of the server, until they are deleted. A restore erases the person again.</li>
      </ul>
      <.form for={@form} id="erase" phx-submit="erase">
        <fieldset>
          <legend>Their comments</legend>
          <label>
            <input type="radio" name="erase[comments]" value="delete" checked /> Delete their comments
          </label>
          <label>
            <input type="radio" name="erase[comments]" value="keep" />
            Keep them, signed Former member and a number
          </label>
        </fieldset>
        <.input
          field={@form[:kept]}
          type="textarea"
          label="What else you keep, and why, for the reply to the person (optional)"
          maxlength="1000"
        />
        <.input
          field={@form[:sure]}
          type="checkbox"
          label="I understand that an erasure cannot be undone"
          required
        />
        <footer><.button type="submit">Erase the data</.button></footer>
      </.form>
    </section>
    """
  end

  attr :request, :map, required: true
  attr :organisation, :map, required: true
  attr :today, Date, required: true
  attr :people, :map, required: true

  @doc "What a request holds."
  def facts(assigns) do
    ~H"""
    <dl id="request-facts">
      <dt>State</dt>
      <dd>
        <.state kind={PrivacyWords.state(@request.state) |> elem(1)}>
          {PrivacyWords.state(@request.state) |> elem(0)}
        </.state>
      </dd>
      <dt>How it came</dt>
      <dd>{PrivacyWords.how(@request.how_received)}</dd>
      <dt :if={@request.identity}>How who asked was checked</dt>
      <dd :if={@request.identity}>{@request.identity}</dd>
      <dt>Received</dt>
      <dd>{ResidentWords.date(@request.received_on)}</dd>
      <dt :if={@request.identity_confirmed_on}>Identity confirmed</dt>
      <dd :if={@request.identity_confirmed_on}>
        {ResidentWords.date(@request.identity_confirmed_on)}
      </dd>
      <dt>Due</dt>
      <dd>
        {ResidentWords.date(due(@request))}<span :if={@request.state == :received}>, {PrivacyWords.days_left(
          Date.diff(due(@request), @today)
        )}</span>
      </dd>
      <dt :if={@request.extended_to}>Extended, because</dt>
      <dd :if={@request.extended_to}>
        {@request.extension_reason} (the person was told on {ResidentWords.date(
          @request.told_of_extension_on
        )})
      </dd>
      <dt :if={@request.refusal_reason}>Refused, because</dt>
      <dd :if={@request.refusal_reason}>{@request.refusal_reason}</dd>
      <dt :if={@request.kept}>What stays</dt>
      <dd :if={@request.kept}>{@request.kept}</dd>
      <dt :if={@request.state == :done}>Comments</dt>
      <dd :if={@request.state == :done}>
        {if @request.keep_comments,
          do: "Kept, signed Former member #{@request.former_number}",
          else: "Deleted"}
      </dd>
      <dt :if={@request.closed_at}>Closed</dt>
      <dd :if={@request.closed_at}>
        {ResidentWords.date(Accounts.local_date(@organisation, @request.closed_at))}
      </dd>
      <dt :if={@request.told_on}>The person was told</dt>
      <dd :if={@request.told_on}>{ResidentWords.date(@request.told_on)}</dd>
    </dl>
    """
  end
end
