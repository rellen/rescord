defmodule RescordWeb.RubyComponents do
  @moduledoc """
  The parts of the pages of the assistant, Ruby (ADR 0069 and ADR 0037):
  the providers of the server and the form of one provider, for a root
  user, and the settings of Ruby in an organisation.

  No part here gets the key of a provider, and none can show one: a page
  of a root user has the last four characters and the day that the key
  was set, and a page of an organisation has the name of a provider and
  the place of the records.
  """

  use RescordWeb, :html

  alias Rescord.Ruby
  alias RescordWeb.RubyWords

  @doc "The providers of the server, or the steps to the first one."
  attr :providers, :list, required: true

  def providers(assigns) do
    ~H"""
    <section aria-labelledby="providers-heading">
      <h2 id="providers-heading">Providers</h2>

      <div :if={@providers == []}>
        <p>This server has no provider yet, so no organisation sees Ruby.</p>
        <ol>
          <li>Add a provider, and type its key.</li>
          <li>Test it. The test costs a part of a cent.</li>
          <li>Offer it to the organisations.</li>
        </ol>
        <p>
          <.button navigate={~p"/root/ruby/new"} variant="primary">
            <.icon name="plus" /> Add a provider
          </.button>
        </p>
      </div>

      <table :if={@providers != []} id="providers">
        <thead>
          <tr>
            <th scope="col">Name</th>
            <th scope="col">Service</th>
            <th scope="col">Model</th>
            <th scope="col">Key</th>
            <th scope="col">Last test</th>
            <th scope="col">Offered</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={provider <- @providers} id={"provider-#{provider.id}"}>
            <td>
              <.link navigate={~p"/root/ruby/#{provider.id}"}>{provider.name}</.link>
            </td>
            <td data-label="Service">{RubyWords.service(provider.kind)}</td>
            <td data-label="Model">{provider.model}</td>
            <td data-label="Key">{RubyWords.key(provider)}</td>
            <td data-label="Last test"><.last_test provider={provider} /></td>
            <td data-label="Offered">{if provider.offered, do: "Yes", else: "No"}</td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  # The last test of a provider, as a state and a day, in a cell of the list.
  attr :provider, :map, required: true

  defp last_test(assigns) do
    {kind, words} = RubyWords.test_state(assigns.provider)
    assigns = assign(assigns, kind: kind, words: words)

    ~H"""
    <.state kind={@kind}>{@words}</.state>
    <span :if={@provider.tested_at}>
      {RubyWords.day(@provider.tested_at)}{if @kind == "alert",
        do: ": " <> RubyWords.failure(@provider.test_result)}
    </span>
    """
  end

  @doc "What Rescord does with the key of a provider."
  def about_keys(assigns) do
    ~H"""
    <section aria-labelledby="keys-heading">
      <h2 id="keys-heading">The keys</h2>
      <p>
        Rescord keeps the key of a provider encrypted. No page shows a key again: only its last
        four characters and the day that it was set. Each change here is in the history, without
        the key.
      </p>
    </section>
    """
  end

  @doc """
  The services, for a new provider: the fields of the form follow the
  service, so the person chooses it first, with a link.
  """
  attr :kind, :atom, required: true

  def services(assigns) do
    ~H"""
    <nav aria-labelledby="service-heading">
      <h2 id="service-heading">Service</h2>
      <ul>
        <li :for={{kind, words} <- RubyWords.services()}>
          <.link patch={~p"/root/ruby/new?#{[kind: kind]}"} aria-current={kind == @kind && "true"}>
            {words}
          </.link>
        </li>
      </ul>
      <p>{RubyWords.about(@kind)} The service stays as it is after you add the provider.</p>
    </nav>
    """
  end

  @doc """
  The test of a saved provider: what the last one found, and the button.
  The result is where a screen reader hears it.
  """
  attr :provider, :map, required: true
  attr :testing?, :boolean, required: true

  def test(assigns) do
    ~H"""
    <section aria-labelledby="test-heading">
      <h2 id="test-heading">Test</h2>
      <p :if={@provider.test_result == :ok} id="test-result" role="status">
        The provider answered, on {RubyWords.time(@provider.tested_at)}.
      </p>
      <p
        :if={@provider.tested_at && @provider.test_result != :ok}
        id="test-result"
        role="alert"
      >
        The test of {RubyWords.time(@provider.tested_at)} failed: {RubyWords.failure(
          @provider.test_result
        )}
      </p>
      <p :if={!@provider.tested_at} id="test-result">Nobody tested this provider with its key yet.</p>
      <p>
        <.button id="test" phx-click="test" disabled={@testing?}>
          <.icon name="arrow-path" spin={@testing?} />
          {if @testing?, do: "Testing", else: "Test"}
        </.button>
      </p>
      <p>
        <small>
          The test sends one small question with the saved settings, and no record of an organisation.
          It costs a part of a cent at a hosted service. Save a change first.
        </small>
      </p>
    </section>
    """
  end

  @doc """
  The form of a provider. `provider` is `nil` for a new one. The fields
  follow the service, and the key field is always empty: the page never
  sends a key back.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :kind, :atom, required: true
  attr :provider, :map, default: nil
  attr :problems, :list, required: true, doc: "each as `{field, words}`"
  attr :retype?, :boolean, default: false, doc: "the person typed a key that was not kept"

  def provider_form(assigns) do
    ~H"""
    <.form for={@form} id="provider" phx-submit="save">
      <.field
        form={@form}
        name={:name}
        problems={@problems}
        label="Name"
        hint="The name that an administrator of an organisation reads."
        autocomplete="off"
      />

      <.field
        :if={@kind in [:ollama, :openai_compatible]}
        form={@form}
        name={:base_url}
        problems={@problems}
        type="url"
        label="Address"
        hint="The address of the model, with its /v1."
        autocomplete="off"
        autocapitalize="none"
        spellcheck="false"
      />

      <.field
        :if={@kind == :bedrock}
        form={@form}
        name={:region}
        problems={@problems}
        label="Region"
        hint="The region of AWS that a request goes to, such as ap-southeast-2."
        autocomplete="off"
        autocapitalize="none"
        spellcheck="false"
      />

      <.field
        form={@form}
        name={:model}
        problems={@problems}
        label="Model"
        hint="The model, by the name that the service gives it."
        autocomplete="off"
        autocapitalize="none"
        spellcheck="false"
      />

      <%!-- The key never comes back from the server: the value is always empty. --%>
      <.input
        :if={@kind != :ollama}
        id="provider_api_key"
        name="provider[api_key]"
        type="password"
        label="Key"
        value=""
        errors={problems_of(@problems, :api_key)}
        hint={RubyWords.key_hint(@provider, @kind, @retype?)}
        autocomplete="new-password"
      />

      <.input
        :if={@provider}
        field={@form[:offered]}
        type="checkbox"
        label="An organisation can choose this provider"
      />

      <details id="provider-limits" open={limits_open?(@problems)}>
        <summary>Limits and prices</summary>

        <.input
          :if={@kind in [:anthropic, :bedrock]}
          id="provider_effort"
          name="provider[effort]"
          type="select"
          label="Effort"
          options={RubyWords.efforts()}
          value={@form[:effort].value}
          errors={problems_of(@problems, :effort)}
          hint="How much the model thinks before it answers. More is slower and costs more."
        />
        <.field
          form={@form}
          name={:max_output_tokens}
          problems={@problems}
          type="number"
          label="Tokens of one answer, at most"
          hint="A token is about four letters. A longer answer is cut short."
          min="1"
        />
        <.field
          form={@form}
          name={:context_tokens}
          problems={@problems}
          type="number"
          label="Tokens of one request, at most"
          hint="The most that Ruby sends the model at once: the conversation and the records that it read."
          min="1"
        />
        <.field
          form={@form}
          name={:default_allowance}
          problems={@problems}
          label="Allowance of an organisation for a month, in US dollars, to start with"
          hint="What a new organisation may spend on Ruby each month. Its administrators can change it."
          inputmode="decimal"
        />

        <p :if={Ruby.priced?(@form[:model].value)}>
          <small>Rescord knows the prices of this model.</small>
        </p>
        <div :if={!Ruby.priced?(@form[:model].value)}>
          <.field
            form={@form}
            name={:price_input}
            problems={@problems}
            label="Price of a million tokens that go in, in US dollars"
            inputmode="decimal"
          />
          <.field
            form={@form}
            name={:price_output}
            problems={@problems}
            label="Price of a million tokens that come out, in US dollars"
            hint="Give both prices, or none. With no price, the use of this model counts as 0, and the allowance of an organisation is never used."
            inputmode="decimal"
          />
        </div>
      </details>

      <footer>
        <.button type="submit" phx-disable-with="Saving">
          {if @provider, do: "Save", else: "Add the provider"}
        </.button>
        <.button navigate={~p"/root/ruby"}>Cancel</.button>
      </footer>
    </.form>
    """
  end

  # A text field of the form of a provider, with the problems of its field
  # beside it.
  attr :form, Phoenix.HTML.Form, required: true
  attr :name, :atom, required: true
  attr :problems, :list, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :hint, :string, default: nil

  attr :rest, :global,
    include: ~w(autocomplete autocapitalize spellcheck inputmode min max step required)

  defp field(assigns) do
    ~H"""
    <.input
      id={@form[@name].id}
      name={@form[@name].name}
      type={@type}
      label={@label}
      value={@form[@name].value}
      errors={problems_of(@problems, @name)}
      hint={@hint}
      {@rest}
    />
    """
  end

  defp problems_of(problems, field), do: for({^field, words} <- problems, do: words)

  @limits [
    :effort,
    :max_output_tokens,
    :context_tokens,
    :default_allowance,
    :price_input,
    :price_output
  ]

  # A closed part would hide the words of a problem in it.
  defp limits_open?(problems), do: Enum.any?(problems, fn {field, _words} -> field in @limits end)

  @doc """
  Where the records of a question go with this provider, as an
  administrator reads it. With `organisations`, the count of the
  organisations that have Ruby on with it, the part says what a change of
  the place does to them.
  """
  attr :place, :string, required: true
  attr :organisations, :integer, default: nil

  def place(assigns) do
    ~H"""
    <section aria-labelledby="place-heading">
      <h2 id="place-heading">Where the records go</h2>
      <p>An administrator of an organisation reads this sentence before they turn Ruby on:</p>
      <blockquote>
        <p>Records go to {@place}.</p>
      </blockquote>
      <p :if={@organisations} id="provider-organisations">
        {RubyWords.organisations(@organisations)} A change of the address or of the region
        changes the sentence, and turns Ruby off for each organisation that agreed to the old
        one, until a person there reads the new sentence and agrees.
      </p>
    </section>
    """
  end

  @doc """
  The part of the settings page of an organisation for Ruby: where it
  stands, and the link to its own page for a person who can change the
  settings.
  """
  attr :organisation, :any, required: true
  attr :status, :any, required: true, doc: "as `Rescord.Ruby.status/1` gives it"
  attr :can_change?, :boolean, required: true

  def settings_line(assigns) do
    ~H"""
    <section aria-labelledby="ruby-heading">
      <h2 id="ruby-heading">Ruby, the assistant</h2>
      <.not_set_up :if={@status == :not_set_up} />
      <.list :if={@status != :not_set_up}>
        <:item title="Ruby">{RubyWords.state(@status)}</:item>
      </.list>
      <p :if={@status != :not_set_up}>
        Ruby answers the questions of a member from the records of {@organisation.name}. It
        thinks with a service that the person who runs this server set up.
      </p>
      <p :if={@can_change? and @status != :not_set_up}>
        <.link id="ruby-settings-link" navigate={~p"/o/#{@organisation.short_name}/settings/ruby"}>
          The settings of Ruby
        </.link>
      </p>
    </section>
    """
  end

  @doc "The words of a server that offers no provider: nothing to turn on."
  def not_set_up(assigns) do
    ~H"""
    <p id="ruby-not-set-up">
      Ruby is not set up on this server. The person who runs the server has not chosen a
      service for it yet, so there is nothing to turn on.
    </p>
    """
  end

  @doc """
  Where the records go, for a person who can change the settings of an
  organisation: the place of the one provider that the server offers, or
  the providers to choose among, each with its place. The radio buttons
  belong to the form `ruby-settings`, which is in the next part. The
  button that agrees to a new place is for the one provider: with a
  choice, the person chooses, and turns Ruby on in the form.
  """
  attr :organisation, :any, required: true
  attr :status, :any, required: true
  attr :offers, :list, required: true, doc: "as `Rescord.Ruby.offers/1` gives them, not empty"
  attr :chosen, :string, default: nil, doc: "the id of the provider of the form"
  attr :agreed_on, :string, default: nil, doc: "the day of the agreement, in words"
  attr :problems, :list, required: true

  def settings_place(assigns) do
    ~H"""
    <section aria-labelledby="where-heading">
      <h2 id="where-heading">Where the records go</h2>
      <p>
        Ruby thinks with a service that the person who runs this server set up. What a member
        writes to Ruby, and the records that Ruby reads to answer, go to that service.
      </p>

      <p :if={match?({:stopped, _why}, @status)} id="ruby-stopped" role="alert">
        {RubyWords.stopped(elem(@status, 1), @organisation.name, true)}
      </p>
      <p :for={words <- problems_of(@problems, :agreed_to)} role="alert">
        Ruby is not on: {words}.
      </p>

      <blockquote :if={match?([_one], @offers)} id="ruby-place">
        <p>Records go to {hd(@offers).place}.</p>
      </blockquote>
      <p :if={match?([_one], @offers) and @status == :on and @agreed_on} id="ruby-agreed">
        <small>{@organisation.name} agreed to this place on {@agreed_on}.</small>
      </p>

      <fieldset :if={match?([_one, _two | _more], @offers)} id="ruby-services">
        <legend>The service of Ruby</legend>
        <%= for offer <- @offers do %>
          <label>
            <input
              type="radio"
              name="ruby[provider_id]"
              value={offer.id}
              form="ruby-settings"
              checked={offer.id == @chosen}
              aria-describedby={"ruby-place-#{offer.id}"}
              required
            />
            {offer.name}
          </label>
          <small id={"ruby-place-#{offer.id}"} data-hint>Records go to {offer.place}.</small>
        <% end %>
      </fieldset>
      <p :for={words <- problems_of(@problems, :provider_id)} role="alert">
        Ruby is not on: {words}.
      </p>

      <form
        :if={@status == {:stopped, :place} and match?([_one], @offers)}
        id="ruby-agree"
        phx-submit="agree"
      >
        <footer><.button type="submit" variant="primary">Agree, and turn Ruby on</.button></footer>
      </form>
    </section>
    """
  end

  @doc """
  The form of the settings of Ruby in an organisation: the switch, the
  allowance of a month, the share of one member (ADR 0117) and the days
  that a conversation is kept.
  """
  attr :organisation, :any, required: true
  attr :status, :any, required: true
  attr :offers, :list, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :problems, :list, required: true

  attr :at_share, :integer,
    default: 0,
    doc: "the count of the members who used their share this month"

  attr :share?, :boolean,
    default: false,
    doc: "whether the organisation gives each member a share"

  def settings_form(assigns) do
    ~H"""
    <section aria-labelledby="does-heading">
      <h2 id="does-heading">What Ruby does here</h2>
      <.form for={@form} id="ruby-settings" phx-submit="save">
        <input
          :if={match?([_one], @offers)}
          type="hidden"
          name={@form[:provider_id].name}
          value={hd(@offers).id}
        />
        <div>
          <label for="ruby-enabled">
            <input type="hidden" name={@form[:enabled].name} value="false" />
            <input
              type="checkbox"
              id="ruby-enabled"
              name={@form[:enabled].name}
              value="true"
              checked={@form[:enabled].value == "true"}
              aria-describedby="ruby-enabled-hint"
            /> Ruby answers the members of {@organisation.name}
          </label>
          <small id="ruby-enabled-hint" data-hint>
            When you turn Ruby on, you agree that the records go to {if match?([_one], @offers),
              do: "the place above",
              else: "the place of the service that you chose"}.
          </small>
        </div>
        <.field
          form={@form}
          name={:allowance}
          problems={@problems}
          label="Allowance for a month, in US dollars"
          inputmode="decimal"
          autocomplete="off"
          hint={allowance_hint(@offers)}
        />
        <.field
          form={@form}
          name={:member_allowance}
          problems={@problems}
          label="Share of one member for a month, in US dollars"
          inputmode="decimal"
          autocomplete="off"
          hint="Leave it empty to let one member use the whole allowance."
        />
        <p :if={@share?} id="ruby-at-share">
          {RescordWeb.Locale.count(@at_share, "member has", "members have")} used their share this month.
        </p>
        <.field
          form={@form}
          name={:retention_days}
          problems={@problems}
          type="number"
          label="Days that a conversation is kept"
          min="1"
          max="3650"
          required
          hint="After that, Rescord deletes it. The records that a member made with Ruby stay."
        />
        <footer><.button type="submit" variant="primary">Save</.button></footer>
      </.form>
      <p>
        A member asks Ruby when their role has the power “{RescordWeb.RoleWords.power(:ruby)}”.
        <.link navigate={~p"/o/#{@organisation.short_name}/roles"}>See the roles</.link>
      </p>
    </section>
    """
  end

  defp allowance_hint([offer]),
    do:
      "When the allowance is used, Ruby answers nobody until the next month. " <>
        "This server starts an organisation at #{RubyWords.dollars(offer.default_allowance)} US dollars."

  defp allowance_hint(_offers),
    do:
      "When the allowance is used, Ruby answers nobody until the next month. " <>
        "Leave the field empty for the amount that this server starts an organisation at."

  @doc """
  The use of the month, from `Rescord.Ruby.use_of_month/2`: how much of
  the allowance went, in a `<meter>` that turns at 80%, words from 80% on,
  and a table of the replies and the cost of each member. It holds counts
  and no word of any conversation. A member has the label of
  `Rescord.Accounts.people/1`, or "A former member" when nothing names
  them any more.
  """
  attr :use, :map, required: true
  attr :allowance, :any, required: true, doc: "the allowance of a month, in whole US cents"
  attr :people, :map, required: true

  def use_of_month(assigns) do
    ~H"""
    <section id="ruby-use" aria-labelledby="use-heading">
      <h2 id="use-heading">The use of {RescordWeb.Locale.month(@use.month)}</h2>
      <p :if={is_integer(@allowance) and @allowance > 0}>
        <label for="ruby-used">{RubyWords.used(@use.cost_microdollars, @allowance)}</label>
        <meter
          id="ruby-used"
          min="0"
          max={@allowance}
          low={div(@allowance * 4, 5)}
          high={div(@allowance * 4, 5)}
          optimum="0"
          value={min(RubyWords.cents_of(@use.cost_microdollars), @allowance)}
        >
          {RubyWords.share(@use.cost_microdollars, @allowance)}
        </meter>
      </p>
      <p
        :if={warning = RubyWords.use_warning(@use.cost_microdollars, @allowance, @use.month)}
        id="ruby-use-warning"
      >
        <.icon name="exclamation-triangle" /> {warning}
      </p>
      <p>
        The counts start on the first day of the month in UTC, as the service bills. They hold no
        word of any conversation, and they stay when a conversation or a member goes.
      </p>
      <div data-scroll>
        <table id="ruby-use-members">
          <caption>The replies and the cost of each member</caption>
          <thead>
            <tr>
              <th scope="col">Member</th>
              <th scope="col">Replies</th>
              <th scope="col">Cost, in US dollars</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={member <- @use.members} :key={member.user_id}>
              <td>{person(@people, member.user_id)}</td>
              <td data-label="Replies">{RescordWeb.Locale.number(member.replies)}</td>
              <td data-label="Cost, in US dollars">
                {RubyWords.about_dollars(member.cost_microdollars)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  @doc """
  What the members said of the answers of the month, as counts with no
  word, and the answers that a member sent to the administrators: each
  with its question, its words, what was wrong and what Ruby read for it.
  An answer that nobody sent shows no word here.
  """
  attr :answers, :map, required: true, doc: "from `Rescord.Ruby.answers_of_month/2`"
  attr :month, Date, required: true
  attr :reports, :list, required: true, doc: "from `Rescord.Ruby.reported_answers/2`"
  attr :people, :map, required: true
  attr :organisation, :map, required: true

  def answers(assigns) do
    ~H"""
    <section id="ruby-answers" aria-labelledby="answers-heading">
      <h2 id="answers-heading">Was each answer right?</h2>
      <p>{RubyWords.answers(@answers, @month)}</p>
      <article
        :for={report <- @reports}
        :key={report.id}
        id={"reported-#{report.id}"}
        aria-labelledby={"reported-heading-#{report.id}"}
      >
        <h3 id={"reported-heading-#{report.id}"}>
          Sent by {person(@people, report.owner_id)}, {RubyWords.moment(
            report.reported_at,
            @organisation
          )}
        </h3>
        <p :if={report.response_to}><strong>The question:</strong> {report.response_to.text}</p>
        <RescordWeb.RubyChatComponents.prose
          text={report.text || ""}
          organisation={@organisation}
          known={Ruby.refs([report])}
        />
        <p :if={report.rating_note}><strong>What was wrong:</strong> {report.rating_note}</p>
        <RescordWeb.RubyChatComponents.steps_done
          id={"reported-steps-#{report.id}"}
          steps={report.steps || []}
        />
      </article>
    </section>
    """
  end

  defp person(people, user_id) do
    case Map.get(people, user_id) do
      %{label: label} -> label
      nil -> "A former member"
    end
  end

  @doc "The removal of a provider, behind a part that is closed at first."
  attr :provider, :map, required: true

  def remove(assigns) do
    ~H"""
    <section aria-labelledby="remove-heading">
      <h2 id="remove-heading">Remove</h2>
      <.confirm id="provider-remove" summary="Remove this provider">
        <p>
          Ruby stops for each organisation that uses this provider. Rescord deletes the key.
          Rescord cannot revoke the key: do that at the service.
        </p>
        <.button id="remove" variant="danger" phx-click="remove">Remove {@provider.name}</.button>
      </.confirm>
    </section>
    """
  end

  @doc "The line of the root page for Ruby: how many providers, and what the last test found."
  attr :providers, :list, required: true

  def root_line(assigns) do
    ~H"""
    <p id="ruby-line">
      <.link navigate={~p"/root/ruby"}>Ruby, the assistant</.link>: {summary(@providers)}.
    </p>
    """
  end

  defp summary([]), do: "no provider yet"

  defp summary([provider]) do
    offered = if provider.offered, do: "offered", else: "not offered"
    "1 provider, #{offered}, #{last_test_words(provider)}"
  end

  defp summary(providers) do
    offered = Enum.count(providers, & &1.offered)
    failed = Enum.count(providers, &(&1.tested_at && &1.test_result != :ok))
    "#{length(providers)} providers, #{offered} offered, #{failed} with a last test that failed"
  end

  defp last_test_words(%{tested_at: nil}), do: "never tested"

  defp last_test_words(%{test_result: :ok, tested_at: at}),
    do: "the last test passed on #{RubyWords.day(at)}"

  defp last_test_words(%{tested_at: at}), do: "the last test failed on #{RubyWords.day(at)}"
end
