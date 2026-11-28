defmodule RescordWeb.RubyComponents do
  @moduledoc """
  The parts of the pages of the assistant, Ruby (ADR 0069 and ADR 0037):
  the providers of the server, and the form of one provider, for a root
  user.

  No part here gets the key of a provider, and none can show one: a page
  has the last four characters and the day that the key was set.
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
            Add a provider
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
          The test sends one small question with the saved settings, and no record of a rescue.
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
          min="1"
        />
        <.field
          form={@form}
          name={:context_tokens}
          problems={@problems}
          type="number"
          label="Tokens of one request, at most"
          min="1"
        />
        <.field
          form={@form}
          name={:default_allowance}
          problems={@problems}
          label="Allowance of an organisation for a month, in US dollars, to start with"
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
        <.button :if={!@provider} navigate={~p"/root/ruby"}>Cancel</.button>
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
  attr :rest, :global, include: ~w(autocomplete autocapitalize spellcheck inputmode min max step)

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

  @doc "Where the records of a question go with this provider, as an administrator reads it."
  attr :place, :string, required: true

  def place(assigns) do
    ~H"""
    <section aria-labelledby="place-heading">
      <h2 id="place-heading">Where the records go</h2>
      <p>An administrator of an organisation reads this sentence before they turn Ruby on:</p>
      <blockquote>
        <p>Records go to {@place}.</p>
      </blockquote>
    </section>
    """
  end

  @doc "The removal of a provider, behind a part that is closed at first."
  attr :provider, :map, required: true

  def remove(assigns) do
    ~H"""
    <section aria-labelledby="remove-heading">
      <h2 id="remove-heading">Remove</h2>
      <details id="provider-remove">
        <summary>Remove this provider</summary>
        <p>
          Ruby stops for each organisation that uses this provider. Rescord deletes the key.
          Rescord cannot revoke the key: do that at the service.
        </p>
        <.button id="remove" phx-click="remove">Remove {@provider.name}</.button>
      </details>
    </section>
    """
  end

  @doc "The line of the root page for Ruby: how many providers, and what the last test found."
  attr :providers, :list, required: true

  def root_line(assigns) do
    ~H"""
    <p id="ruby-line">
      <a href={~p"/root/ruby"}>Ruby, the assistant</a>: {summary(@providers)}.
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
