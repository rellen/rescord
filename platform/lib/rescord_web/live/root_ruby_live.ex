defmodule RescordWeb.RootRubyLive do
  @moduledoc """
  The providers of the assistant, Ruby, for a root user (ADR 0069): the
  list at `/root/ruby`, a new provider at `/root/ruby/new`, and one
  provider at `/root/ruby/<id>`. The live session lets only a root user in,
  and the policy of a provider refuses each other person.

  A provider has no setting in the environment (ADR 0068): this page is
  where it is set.

  The key of a provider goes from the form to the action, and nowhere
  else. No assign holds it, the page never sends one back, and the form
  that the page builds again after a refusal has no key in it. The fields
  of a new provider follow its service, so the person chooses the service
  first, with a link, and the page needs no event for each change of a
  field: a key that a person typed is sent one time, with the form.

  "Test" runs in a task of the page, so the page answers while the service
  does. The page opens again after a write.
  """

  use RescordWeb, :live_view

  import RescordWeb.RubyComponents

  alias Rescord.Ruby
  alias RescordWeb.RubyWords

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, problems: [], retype?: false, testing?: false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, problems: [], retype?: false)
    {:noreply, open(socket, socket.assigns.live_action, params)}
  end

  defp open(socket, :index, _params) do
    assign(socket,
      page_title: "Ruby",
      providers: Ruby.providers!(actor: socket.assigns.current_user, query: [sort: [:name]])
    )
  end

  defp open(socket, :new, params) do
    kind =
      case RubyWords.service_of(params["kind"]) do
        {:ok, kind} -> kind
        :error -> :anthropic
      end

    assign(socket,
      page_title: "A new provider",
      provider: nil,
      kind: kind,
      form: fields(Map.put(Ruby.provider_defaults(kind), :default_allowance, 2_000))
    )
  end

  defp open(socket, :provider, %{"id" => id}) do
    case Ruby.provider(id, actor: socket.assigns.current_user) do
      {:ok, %{} = provider} ->
        assign(socket,
          page_title: provider.name,
          provider: provider,
          kind: provider.kind,
          organisations: Ruby.organisations_with(provider),
          form: fields(provider)
        )

      # No provider has this id, or the id is none.
      _none ->
        socket
        |> put_flash(:error, "This server has no such provider.")
        |> push_navigate(to: ~p"/root/ruby")
    end
  end

  # The fields of the form, as text, from a provider or from the defaults
  # of a kind. The key is no field of it.
  defp fields(values) do
    to_form(
      %{
        "name" => values |> Map.get(:name) |> to_string(),
        "model" => values |> Map.get(:model) |> to_string(),
        "base_url" => values |> Map.get(:base_url) |> to_string(),
        "region" => values |> Map.get(:region) |> to_string(),
        "offered" => values |> Map.get(:offered, false) |> to_string(),
        "effort" => values |> Map.get(:effort, :low) |> to_string(),
        "max_output_tokens" => values |> Map.get(:max_output_tokens) |> to_string(),
        "context_tokens" => values |> Map.get(:context_tokens) |> to_string(),
        "default_allowance" => RubyWords.dollars(Map.get(values, :default_allowance)),
        "price_input" => RubyWords.price(Map.get(values, :price_input)),
        "price_output" => RubyWords.price(Map.get(values, :price_output))
      },
      as: :provider
    )
  end

  @impl true
  def handle_event("save", %{"provider" => params}, socket) when is_map(params) do
    %{current_user: actor, kind: kind, provider: provider} = socket.assigns
    key = if kind == :ollama, do: nil, else: non_blank(params["api_key"])

    result =
      with {:ok, attributes} <- attributes(params, kind) do
        case provider do
          nil ->
            Ruby.add_provider(Map.merge(attributes, %{kind: kind, api_key: key}), actor: actor)

          provider ->
            attributes = Map.put(attributes, :offered, params["offered"] == "true")
            Ruby.save_provider(provider, attributes, key, actor: actor)
        end
      end

    case result do
      {:ok, saved} ->
        words = if provider, do: "#{saved.name} is saved.", else: "#{saved.name} is added."

        {:noreply,
         socket |> put_flash(:info, words) |> push_navigate(to: ~p"/root/ruby/#{saved.id}")}

      {:error, error} ->
        problems = if is_list(error), do: error, else: Ruby.problems(error)

        {:noreply,
         assign(socket,
           problems: problems,
           # The key is not in the form that the page builds again.
           form: typed_form(Map.delete(params, "api_key"), as: :provider),
           retype?: key != nil
         )}
    end
  end

  def handle_event("test", _params, %{assigns: %{provider: %{} = provider}} = socket) do
    if socket.assigns.testing? do
      {:noreply, socket}
    else
      actor = socket.assigns.current_user

      {:noreply,
       socket
       |> assign(testing?: true, problems: [])
       |> start_async(:test, fn -> Ruby.test_provider(provider, actor: actor) end)}
    end
  end

  def handle_event("remove", _params, %{assigns: %{provider: %{} = provider}} = socket) do
    case Ruby.remove_provider(provider, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "#{provider.name} is removed, and Rescord deleted its key.")
         |> push_navigate(to: ~p"/root/ruby")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Ruby.problems(error))}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:test, {:ok, {:ok, provider}}, socket) do
    # The test wrote its result. The form keeps what the person typed.
    {:noreply, assign(socket, testing?: false, provider: provider)}
  end

  def handle_async(:test, _failed, socket) do
    {:noreply,
     assign(socket, testing?: false, problems: [{nil, "The test did not run. Try again."}])}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The attributes of the form for the actions, by the fields that the
  # kind has. An amount of money that is none is a problem of its field.
  defp attributes(params, kind) do
    money = [
      default_allowance: RubyWords.cents(params["default_allowance"] || ""),
      price_input: optional(params["price_input"], &RubyWords.millionths/1),
      price_output: optional(params["price_output"], &RubyWords.millionths/1)
    ]

    problems =
      for {field, :error} <- money do
        {field, "give an amount in US dollars, such as 20 or 0.50"}
      end

    if problems == [] do
      {:ok,
       %{
         name: non_blank(params["name"]),
         model: non_blank(params["model"]),
         max_output_tokens: non_blank(params["max_output_tokens"]),
         context_tokens: non_blank(params["context_tokens"])
       }
       |> Map.merge(Map.new(money, fn {field, {:ok, amount}} -> {field, amount} end))
       |> Map.merge(of_kind(params, kind))}
    else
      {:error, problems}
    end
  end

  defp optional(text, parse) do
    case non_blank(text) do
      nil -> {:ok, nil}
      text -> parse.(text)
    end
  end

  # A field that the form of a kind does not have is not sent.
  defp of_kind(params, kind) when kind in [:ollama, :openai_compatible],
    do: %{base_url: non_blank(params["base_url"])}

  defp of_kind(params, :bedrock),
    do: %{region: non_blank(params["region"]), effort: non_blank(params["effort"])}

  defp of_kind(params, :anthropic), do: %{effort: non_blank(params["effort"])}

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <.header icon={Icons.section(:ruby)}>
        <:crumb navigate={~p"/root"}>Root</:crumb>
        Ruby
        <:subtitle>
          The services that Ruby, the assistant, can think with on this server. An organisation
          chooses among the ones that are offered.
        </:subtitle>
        <:actions :if={@providers != []}>
          <.button navigate={~p"/root/ruby/new"} variant="primary"><.icon name="plus" />
          Add a provider</.button>
        </:actions>
      </.header>

      <.providers providers={@providers} />
      <.about_keys />
    </Layouts.app>
    """
  end

  def render(%{live_action: :new} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <.header icon={Icons.section(:ruby)}>
        <:crumb navigate={~p"/root"}>Root</:crumb>
        <:crumb navigate={~p"/root/ruby"}>Ruby</:crumb>
        A new provider
        <:subtitle>The fields follow the service: choose it first.</:subtitle>
      </.header>

      <.services kind={@kind} />

      <section aria-labelledby="provider-heading">
        <h2 id="provider-heading">The provider</h2>
        <.problems list={general(@problems)} />
        <.provider_form form={@form} kind={@kind} problems={@problems} retype?={@retype?} />
      </section>

      <.place place={place(@form, @kind)} />
    </Layouts.app>
    """
  end

  def render(%{live_action: :provider} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <.header icon={Icons.section(:ruby)}>
        <:crumb navigate={~p"/root"}>Root</:crumb>
        <:crumb navigate={~p"/root/ruby"}>Ruby</:crumb>
        {@provider.name}
        <:subtitle>A provider of this server, with the service {RubyWords.service(@kind)}.</:subtitle>
      </.header>

      <.problems list={general(@problems)} />

      <.test provider={@provider} testing?={@testing?} />

      <section aria-labelledby="provider-heading">
        <h2 id="provider-heading">The provider</h2>
        <.provider_form
          form={@form}
          kind={@kind}
          provider={@provider}
          problems={@problems}
          retype?={@retype?}
        />
      </section>

      <.place place={Ruby.place(@provider)} organisations={@organisations} />
      <.remove provider={@provider} />
    </Layouts.app>
    """
  end

  # A problem with no field, or of a field that this form does not show,
  # is above the form.
  @shown ~w(name model base_url region api_key effort max_output_tokens context_tokens
            default_allowance price_input price_output)a

  defp general(problems) do
    for {field, words} <- problems, field not in @shown do
      if field, do: "#{field}: #{words}", else: words
    end
  end

  # The place of a provider that is not saved yet, from what the form holds.
  defp place(form, kind) do
    Ruby.place(%{
      kind: kind,
      base_url: non_blank(form[:base_url].value),
      region: non_blank(form[:region].value)
    })
  end
end
