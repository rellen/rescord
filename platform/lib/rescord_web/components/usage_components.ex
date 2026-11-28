defmodule RescordWeb.UsageComponents do
  @moduledoc """
  The parts of the page of the usage counts, `/root/usage` (ADR 0098 and
  ADR 0037): where the counts stand, the form of the mode and the address,
  the token, the test, the document that a send writes, the counts of the
  last 30 days, and the installation id.

  No part gets the token, and none can show one: the page has its last
  four characters and the day that it was set.
  """

  use RescordWeb, :html

  alias RescordWeb.UsageWords

  @doc "What the counts are, and where they stand."
  attr :settings, :map, required: true

  def status(assigns) do
    {kind, words} = UsageWords.result(assigns.settings.last_result, assigns.settings.last_status)
    assigns = assign(assigns, kind: kind, words: words)

    ~H"""
    <section aria-labelledby="usage-status-heading">
      <h2 id="usage-status-heading">Where the counts stand</h2>
      <p>
        Rescord counts how often each feature is used on this server, for each day: the pages
        that open, the actions that people run, and the files that Rescord sends. A count holds
        no person, no organisation and no record. You decide whether the counts stay here or go
        to one address that you name.
      </p>
      <dl id="usage-status">
        <dt>Mode</dt>
        <dd>{UsageWords.mode(@settings.mode)}</dd>
        <dt>Address</dt>
        <dd>{@settings.endpoint || "None"}</dd>
        <dt>Format</dt>
        <dd>{UsageWords.format(@settings.format)}</dd>
        <dt>Token</dt>
        <dd>{UsageWords.token(@settings)}</dd>
        <dt :if={@settings.mode == :send}>Last day sent</dt>
        <dd :if={@settings.mode == :send}>{UsageWords.day(@settings.last_sent_day)}</dd>
        <dt :if={@settings.mode == :send}>Last send</dt>
        <dd :if={@settings.mode == :send}>
          <.state kind={@kind}>{@words}</.state>
          <span :if={@settings.last_attempt_at}>{UsageWords.time(@settings.last_attempt_at)}</span>
        </dd>
      </dl>
    </section>
    """
  end

  @doc "The form of the mode, the format and the address."
  attr :form, Phoenix.HTML.Form, required: true
  attr :problems, :list, required: true, doc: "each as `{field, words}`"

  def settings_form(assigns) do
    ~H"""
    <section aria-labelledby="usage-mode-heading">
      <h2 id="usage-mode-heading">Where the counts go</h2>
      <.form for={@form} id="usage-settings" phx-submit="save">
        <fieldset id="usage-modes">
          <legend>Mode</legend>
          <%= for {mode, words, hint} <- UsageWords.modes() do %>
            <label>
              <input
                type="radio"
                name={@form[:mode].name}
                value={mode}
                checked={to_string(mode) == to_string(@form[:mode].value)}
                aria-describedby={"usage-mode-#{mode}"}
              />
              {words}
            </label>
            <small id={"usage-mode-#{mode}"} data-hint>{hint}</small>
          <% end %>
        </fieldset>

        <.input
          id={@form[:endpoint].id}
          name={@form[:endpoint].name}
          type="url"
          label="Address"
          value={@form[:endpoint].value}
          errors={problems_of(@problems, :endpoint)}
          hint="Rescord sends each full day there with POST, in the mode that sends. It follows no redirect."
          autocomplete="off"
          spellcheck="false"
          inputmode="url"
          placeholder="https://collector.example.org/v1/metrics"
        />

        <fieldset id="usage-formats">
          <legend>Format</legend>
          <%= for {format, words, hint} <- UsageWords.formats() do %>
            <label>
              <input
                type="radio"
                name={@form[:format].name}
                value={format}
                checked={to_string(format) == to_string(@form[:format].value)}
                aria-describedby={"usage-format-#{format}"}
              />
              {words}
            </label>
            <small id={"usage-format-#{format}"} data-hint>{hint}</small>
          <% end %>
        </fieldset>

        <p :for={{nil, words} <- @problems} role="alert">{words}</p>

        <footer>
          <.button type="submit" variant="primary" phx-disable-with="Saving">Save</.button>
        </footer>
      </.form>
    </section>
    """
  end

  @doc """
  The token of the address, and the test. The token field is always
  empty: the page never sends a token back.
  """
  attr :settings, :map, required: true
  attr :problems, :list, required: true
  attr :testing?, :boolean, required: true

  def token_and_test(assigns) do
    {kind, words} = UsageWords.result(assigns.settings.test_result, assigns.settings.test_status)
    assigns = assign(assigns, kind: kind, words: words)

    ~H"""
    <section aria-labelledby="usage-token-heading">
      <h2 id="usage-token-heading">The token</h2>
      <p id="usage-token">{UsageWords.token(@settings)}.</p>
      <form id="usage-token-form" phx-submit="save_token">
        <.input
          id="usage_token"
          name="usage[token]"
          type="password"
          label="A new token"
          value=""
          errors={problems_of(@problems, :token)}
          hint="Rescord sends it as authorization: Bearer, and only to an address with https:// or to this machine. It keeps it encrypted, and no page shows it again."
          autocomplete="off"
        />
        <footer>
          <.button type="submit" phx-disable-with="Saving">Save the token</.button>
          <.button
            :if={@settings.token_set_at}
            type="button"
            phx-click="forget_token"
            data-confirm="Delete the token? A send then has none."
          >
            Delete the token
          </.button>
        </footer>
      </form>
    </section>

    <section aria-labelledby="usage-test-heading">
      <h2 id="usage-test-heading">Send a test</h2>
      <p :if={@settings.tested_at} id="usage-test-result" role="status">
        <.state kind={@kind}>{@words}</.state>
        {UsageWords.time(@settings.tested_at)}
      </p>
      <p :if={!@settings.tested_at} id="usage-test-result">Nobody sent a test yet.</p>
      <p>
        <.button
          id="usage-test"
          phx-click="test"
          disabled={@testing? or is_nil(@settings.endpoint)}
        >
          <.icon name="arrow-path" spin={@testing?} />
          {if @testing?, do: "Sending", else: "Send a test"}
        </.button>
      </p>
      <p>
        <small>
          A test sends the form of the document with no count, to the saved address, in any mode.
          Save a change first.
        </small>
      </p>
    </section>
    """
  end

  @doc "The document that a send writes, and what each part of it is."
  attr :settings, :map, required: true
  attr :day, Date, default: nil, doc: "the day of the document, or `nil` with no count yet"
  attr :document, :string, required: true

  def document(assigns) do
    ~H"""
    <section aria-labelledby="usage-document-heading">
      <h2 id="usage-document-heading">What Rescord sends</h2>
      <p :if={@day}>
        The document of {UsageWords.day(@day)}, the last full day with a count, character for
        character as a send writes it:
      </p>
      <p :if={!@day}>
        No full day has a count yet. A document of a day has this form, with a point for each
        count:
      </p>
      <pre id="usage-document" data-wrap><code>{@document}</code></pre>

      <h3>The parts of it</h3>
      <dl :if={@settings.format == :otlp}>
        <dt><code>service.name</code>, <code>service.version</code></dt>
        <dd>Rescord, and its version.</dd>
        <dt><code>service.instance.id</code></dt>
        <dd>
          The random id of this installation, below. It comes from nothing of the server, so that a
          receiver can put the days of one server together.
        </dd>
        <dt><code>rescord.usage.count</code></dt>
        <dd>
          A sum of the day, with the temporality delta: one point for each feature, kind and item,
          from the midnight of the day to the next one, in UTC.
        </dd>
        <dt><code>feature</code>, <code>kind</code>, <code>item</code></dt>
        <dd>
          A feature of the list below; a page, an action or a file; and its name as the code of
          Rescord names it.
        </dd>
      </dl>
      <dl :if={@settings.format == :json}>
        <dt><code>schema</code></dt>
        <dd>The form of the document: <code>rescord.usage/1</code>.</dd>
        <dt><code>installation</code></dt>
        <dd>
          The random id of this installation, below. It comes from nothing of the server.
        </dd>
        <dt><code>rescord</code>, <code>day</code></dt>
        <dd>The version of Rescord, and the day in UTC.</dd>
        <dt><code>counts</code></dt>
        <dd>
          For each feature, kind and item: how many times, on that day, on this server.
        </dd>
      </dl>

      <h3>What is never in it</h3>
      <ul id="usage-never">
        <li>who did it: no user, member, role, address of a client or browser;</li>
        <li>where: no organisation, name of a rescue or host name;</li>
        <li>what: no record, name, text that a person typed, file name or search;</li>
        <li>when, closer than the day;</li>
        <li>how many records a rescue has, or how many people use the server.</li>
      </ul>
      <p>
        A day with one person on the server still says what that person used on that day. That is
        why the counts stay here until you name an address.
      </p>
    </section>
    """
  end

  @doc "The counts of the last 30 days, by feature, with the items of each."
  attr :features, :list,
    required: true,
    doc: "each as `%{feature, page, action, file, items: [{kind, item, count}]}`"

  def counts(assigns) do
    ~H"""
    <section aria-labelledby="usage-counts-heading">
      <h2 id="usage-counts-heading">The last 30 days</h2>
      <p :if={@features == []} id="usage-none">
        No count yet. The counts of the last minute reach this page within a minute.
      </p>
      <table :if={@features != []} id="usage-counts">
        <thead>
          <tr>
            <th scope="col">Feature</th>
            <th scope="col">Pages opened</th>
            <th scope="col">Actions</th>
            <th scope="col">Files</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @features} id={"usage-#{row.feature}"}>
            <td>{UsageWords.feature(row.feature)}</td>
            <td data-label="Pages opened">{row.page}</td>
            <td data-label="Actions">{row.action}</td>
            <td data-label="Files">{row.file}</td>
          </tr>
        </tbody>
      </table>

      <details :for={row <- @features} id={"usage-items-#{row.feature}"}>
        <summary>{UsageWords.feature(row.feature)}: each page, action and file</summary>
        <table>
          <thead>
            <tr>
              <th scope="col">Item</th>
              <th scope="col">Kind</th>
              <th scope="col">Count</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{kind, item, count} <- row.items}>
              <td><code>{item}</code></td>
              <td data-label="Kind">{kind}</td>
              <td data-label="Count">{count}</td>
            </tr>
          </tbody>
        </table>
      </details>
    </section>
    """
  end

  @doc "The installation id, with the buttons that make a new one and delete the counts."
  attr :settings, :map, required: true

  def installation(assigns) do
    ~H"""
    <section aria-labelledby="usage-installation-heading">
      <h2 id="usage-installation-heading">This installation</h2>
      <p :if={@settings.installation_id} id="usage-installation">
        Its id is <code>{@settings.installation_id}</code>.
      </p>
      <p :if={!@settings.installation_id} id="usage-installation">
        It gets a random id at the first save.
      </p>
      <p>
        A new id cuts the tie between what was sent before and what comes next. Deleting the counts
        empties the table of the counts on this server, and sends nothing.
      </p>
      <footer>
        <.button
          :if={@settings.installation_id}
          id="usage-new-installation"
          phx-click="new_installation"
          data-confirm="Make a new id? A receiver cannot tie the days to come to the days before."
        >
          Make a new id
        </.button>
        <.button
          id="usage-forget"
          phx-click="forget_counts"
          data-confirm="Delete each count that this server stored?"
        >
          Delete the counts
        </.button>
      </footer>
    </section>
    """
  end

  defp problems_of(problems, field), do: for({^field, words} <- problems, do: words)
end
