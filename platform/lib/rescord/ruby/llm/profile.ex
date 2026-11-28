defmodule Rescord.Ruby.LLM.Profile do
  @moduledoc """
  The model that Ruby talks to, and how: the service, the model, the key,
  the address, the limits of one request, and the prices.

  A profile comes from a provider: a row of `Rescord.Ruby.Provider`, which a
  root user sets on a page (ADR 0069). No setting of a provider is read from
  the environment or from the application config (ADR 0068).

  This module holds the rules of a provider in one place:

    * `problems/1` says what is wrong with the values of a provider, by
      field. The validation of the resource calls it, so the page shows the
      words beside the field. It needs no key: it runs for a form.
    * `from_provider/1` makes the profile of a reply, with the key. Only the
      job of a reply and the button "Test" call it, with a provider whose
      key `Rescord.Ruby.LLM` decrypted.

  Nothing else in Ruby names a service: `model_spec/1` and `req_llm_opts/1`
  turn the profile into what `AshAi.ToolLoop` passes to ReqLLM.

  A profile holds the key. `inspect/1` of a profile does not show it.
  """

  alias Rescord.Ruby.LLM.Cost
  alias Shoddy.Keywords

  # The kinds of a provider, as the resource names them, and the provider of
  # ReqLLM that each one uses.
  @kinds %{
    anthropic: :anthropic,
    bedrock: :amazon_bedrock,
    ollama: :ollama,
    openai_compatible: :openai_compatible
  }

  # The kinds whose host is fixed and outside the rescue. They always need a
  # key, and an address in front of them (a gateway) must have TLS.
  @hosted [:anthropic, :bedrock]

  @efforts [:low, :medium, :high]

  @this_machine ["localhost", "127.0.0.1", "::1"]

  @enforce_keys [:provider, :model]
  @derive {Inspect, except: [:api_key]}
  defstruct [
    :provider,
    :model,
    :api_key,
    :base_url,
    :region,
    # {input, output, cache read, cache write of one hour}, or nil for a
    # model with no bill. See `Rescord.Ruby.LLM.Cost`.
    :prices,
    effort: :low,
    max_output_tokens: 4_096,
    # The most tokens of one request, with the tools and the system prompt.
    context_tokens: 60_000,
    receive_timeout: 120_000,
    total_timeout: 300_000
  ]

  @type t :: %__MODULE__{
          provider: :anthropic | :amazon_bedrock | :ollama | :openai_compatible,
          model: String.t(),
          api_key: String.t() | nil,
          base_url: String.t() | nil,
          region: String.t() | nil,
          prices: Cost.prices() | nil,
          effort: :low | :medium | :high,
          max_output_tokens: pos_integer,
          context_tokens: pos_integer,
          receive_timeout: pos_integer,
          total_timeout: pos_integer
        }

  @typedoc "What is wrong with a provider: the field, and words for the page."
  @type problem :: {atom, String.t()}

  @doc "The kinds of a provider."
  @spec kinds() :: [atom]
  def kinds, do: Map.keys(@kinds)

  @common %{effort: :low, max_output_tokens: 4_096}

  @defaults %{
    anthropic: %{model: "claude-opus-5-5", context_tokens: 60_000},
    bedrock: %{context_tokens: 60_000},
    ollama: %{base_url: "http://localhost:11434/v1", context_tokens: 32_000},
    openai_compatible: %{context_tokens: 32_000}
  }

  @doc """
  The values that a provider of this kind has when the root user gives
  none. The form of the page shows them in its fields.
  """
  @spec defaults(atom) :: map
  def defaults(kind), do: Map.merge(@common, Map.get(@defaults, kind, %{}))

  @doc """
  What is wrong with the values of a provider. An empty list when nothing
  is.

  `provider` is a record of `Rescord.Ruby.Provider`, or a map with the same
  keys. A key counts as present when `api_key` is a text, or when
  `key_set_at` says that the row has one stored: a form that changes
  another field does not hold the key, and never decrypts it.
  """
  @spec problems(map) :: [problem]
  def problems(provider) do
    fields = read(provider)

    if is_map_key(@kinds, fields.kind) do
      Enum.flat_map(
        [&model/1, &key/1, &region/1, &address/1, &effort/1, &limits/1, &prices/1],
        fn rule -> List.wrap(rule.(fields)) end
      )
    else
      [kind: "choose the service"]
    end
  end

  @doc """
  The profile of a provider, with its key, or what is wrong with it.

  It refuses a provider whose stored key is not in `api_key`: a caller that
  did not decrypt the key must not send a request with none.
  """
  @spec from_provider(map) :: {:ok, t} | {:error, [problem]}
  def from_provider(provider) do
    fields = read(provider)

    case problems(provider) do
      [] when fields.key_stored? and fields.api_key == nil ->
        {:error, [api_key: "the key of the provider was not opened"]}

      [] ->
        {:ok,
         struct!(__MODULE__, %{
           provider: Map.fetch!(@kinds, fields.kind),
           model: fields.model,
           api_key: fields.api_key,
           base_url: fields.base_url,
           region: fields.region,
           prices: prices_of(fields),
           effort: fields.effort,
           max_output_tokens: fields.max_output_tokens,
           context_tokens: fields.context_tokens
         })}

      problems ->
        {:error, problems}
    end
  end

  @doc """
  The most tokens of one request with this provider: its own value, or the
  one of its kind. It needs no key.
  """
  @spec context_tokens(map) :: pos_integer
  def context_tokens(provider), do: read(provider).context_tokens

  @read [:model, :base_url, :region, :effort, :max_output_tokens, :context_tokens] ++
          [:price_input, :price_output]

  # The values of the provider with the defaults of its kind. A value that
  # is nil or an empty text counts as absent.
  defp read(provider) do
    kind = Map.get(provider, :kind)

    given =
      for name <- @read, value = Map.get(provider, name), value not in [nil, ""], into: %{} do
        {name, value}
      end

    # A key that was not loaded is a struct of Ash, and not a text.
    api_key =
      case Map.get(provider, :api_key) do
        key when is_binary(key) and key != "" -> key
        _other -> nil
      end

    %{model: nil, base_url: nil, region: nil, price_input: nil, price_output: nil}
    |> Map.merge(defaults(kind))
    |> Map.merge(given)
    |> Map.merge(%{
      kind: kind,
      api_key: api_key,
      key_stored?: Map.get(provider, :key_set_at) != nil
    })
  end

  defp key?(fields), do: fields.api_key != nil or fields.key_stored?

  defp model(%{model: nil}), do: {:model, "name the model"}
  defp model(_fields), do: nil

  defp key(%{kind: kind} = fields) when kind in @hosted do
    if not key?(fields), do: {:api_key, "this service needs a key"}
  end

  # A key that goes to Ollama is a mistake: it would go over plain HTTP.
  defp key(%{kind: :ollama} = fields) do
    if key?(fields), do: {:api_key, "Ollama takes no key"}
  end

  defp key(_fields), do: nil

  defp region(%{kind: :bedrock, region: nil}), do: {:region, "Amazon Bedrock needs a region"}
  defp region(_fields), do: nil

  defp address(%{kind: :openai_compatible, base_url: nil}),
    do: {:base_url, "this service needs an address"}

  defp address(%{base_url: nil}), do: nil

  # ReqLLM makes the host of Bedrock from the region. An address would do
  # nothing, and the page would name a place that no request goes to.
  defp address(%{kind: :bedrock}), do: {:base_url, "Amazon Bedrock takes no address"}

  defp address(%{kind: kind, base_url: url} = fields) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["http", "https"] or uri.host in [nil, ""] ->
        {:base_url, "the address starts with http:// or https://"}

      uri.scheme == "https" ->
        nil

      kind in @hosted ->
        {:base_url, "the address of a hosted service starts with https://"}

      # A key never goes over plain HTTP, except to this machine. So only
      # a model that asks for no key, on this machine or on a private
      # network, may go without TLS.
      key?(fields) and uri.host not in @this_machine ->
        {:base_url, "a key goes only to an address that starts with https://"}

      true ->
        nil
    end
  end

  defp effort(%{effort: effort}) when effort in @efforts, do: nil
  defp effort(_fields), do: {:effort, "the effort is low, medium or high"}

  defp limits(%{max_output_tokens: answer, context_tokens: request}) do
    cond do
      not is_integer(answer) or answer not in 256..32_000 ->
        {:max_output_tokens, "the limit of an answer is from 256 to 32,000 tokens"}

      not is_integer(request) or request not in 8_000..200_000 ->
        {:context_tokens, "the limit of a request is from 8,000 to 200,000 tokens"}

      answer >= request ->
        {:max_output_tokens, "the limit of an answer is below the limit of a request"}

      true ->
        nil
    end
  end

  defp prices(%{price_input: nil, price_output: nil}), do: nil

  defp prices(%{price_input: input, price_output: output})
       when is_integer(input) and input >= 0 and is_integer(output) and output >= 0,
       do: nil

  defp prices(%{price_input: nil}), do: {:price_input, "give both prices, or none"}
  defp prices(%{price_output: nil}), do: {:price_output, "give both prices, or none"}
  defp prices(_fields), do: {:price_input, "a price is a whole number that is not negative"}

  # The prices of the table of Rescord for a model that it has, or else
  # those that the root user gave. Rescord knows no cache price of a model
  # that is not in its table, so it prices each token of the prompt as
  # input.
  defp prices_of(%{model: model, price_input: input, price_output: output}) do
    case Cost.prices(model) do
      nil when is_integer(input) and is_integer(output) -> {input, output, input, input}
      prices -> prices
    end
  end

  @doc """
  Whether the data of a request leaves the server, and where it goes.

  It takes a profile, or a provider with no key: the page of the root user
  and `Rescord.Ruby.available?/2` ask it, and neither decrypts a key.
  """
  @spec destination(t | map) ::
          :this_server | {:address, String.t()} | {:hosted, String.t()} | :unknown
  def destination(%__MODULE__{} = profile),
    do: destination(profile.provider, profile.base_url, profile.region)

  def destination(%{kind: kind} = provider) do
    fields = read(provider)
    destination(Map.get(@kinds, kind), fields.base_url, fields.region)
  end

  defp destination(:anthropic, nil, _region),
    do: {:hosted, "Anthropic, in the United States and other countries"}

  defp destination(:amazon_bedrock, _url, region) when is_binary(region),
    do: {:hosted, "Amazon Bedrock, from the region #{region}"}

  # An address that the root user set. Rescord cannot know who runs the
  # machine behind a name, so the page shows the name and says no more.
  defp destination(_provider, url, _region) when is_binary(url) do
    case URI.parse(url).host do
      host when host in @this_machine -> :this_server
      host when is_binary(host) and host != "" -> {:address, host}
      _none -> :unknown
    end
  end

  # A form that is not complete yet: no kind, or no address.
  defp destination(_provider, _url, _region), do: :unknown

  @doc """
  The words of the place, as the settings page of an organisation shows
  them. `Rescord.Ruby.Settings` keeps them in `agreed_words` when an
  administrator agrees, for the history. Code never compares them: a
  release may change a word. `place_key/1` is what code compares.
  """
  @spec place(t | map) :: String.t()
  def place(profile_or_provider) do
    case destination(profile_or_provider) do
      {:hosted, words} -> words
      :this_server -> "this server"
      {:address, host} -> "the model at the address #{host}, which a root user of this server set"
      :unknown -> "a place that is not set yet"
    end
  end

  @doc """
  The place as a short text that code compares: `"anthropic"`,
  `"bedrock:ap-southeast-2"`, `"this_server"`, or `"address:"` and the
  whole address. `nil` for a provider that is not complete.

  `Rescord.Ruby.Settings` keeps it in `agreed_destination` when an
  administrator agrees. A change of the kind, of the address or of the
  region of a provider changes it. A change of the model, of a limit or of
  the key does not.
  """
  @spec place_key(t | map) :: String.t() | nil
  def place_key(%__MODULE__{} = profile),
    do: place_key(profile.provider, profile.base_url, profile.region)

  def place_key(%{kind: kind} = provider) do
    fields = read(provider)
    place_key(Map.get(@kinds, kind), fields.base_url, fields.region)
  end

  defp place_key(provider, url, region) do
    case destination(provider, url, region) do
      {:hosted, _words} when provider == :amazon_bedrock -> "bedrock:" <> region
      {:hosted, _words} -> "anthropic"
      :this_server -> "this_server"
      {:address, _host} -> "address:" <> url
      :unknown -> nil
    end
  end

  @doc """
  Whether the place of the provider is the one that an administrator
  agreed to. A provider that is not complete has no place, and a row that
  nobody agreed to has none either: neither is agreed.
  """
  @spec agreed?(t | map, String.t() | nil) :: boolean
  def agreed?(profile_or_provider, agreed),
    do: is_binary(agreed) and place_key(profile_or_provider) == agreed

  @doc """
  The model as ReqLLM takes it. A model of the catalogue of ReqLLM is a
  text such as `"anthropic:claude-opus-5-5"`, which brings its limits and
  its rules for thinking. A local model is a map, which ReqLLM takes with
  no catalogue.
  """
  @spec model_spec(t) :: String.t() | map
  def model_spec(%__MODULE__{provider: :anthropic, model: model}), do: "anthropic:" <> model

  def model_spec(%__MODULE__{provider: :amazon_bedrock, model: model}),
    do: "amazon_bedrock:" <> model

  def model_spec(%__MODULE__{provider: :ollama, model: model}),
    do: %{provider: :ollama, id: model}

  def model_spec(%__MODULE__{provider: :openai_compatible, model: model, base_url: url}),
    do: %{provider: :openai, id: model, base_url: url}

  @doc """
  The options of each request, for `req_llm_opts:` of `AshAi.ToolLoop`.

  `max_tokens` is always set: without it ReqLLM asks for the whole output
  limit of the model, 128,000 tokens for a Claude 5 model.
  """
  @spec req_llm_opts(t) :: keyword
  def req_llm_opts(%__MODULE__{} = profile) do
    [
      max_tokens: profile.max_output_tokens,
      receive_timeout: profile.receive_timeout,
      total_timeout: profile.total_timeout
    ]
    |> Keywords.put_present(:api_key, profile.api_key)
    |> Keywords.put_present(:base_url, base_url(profile))
    |> Keyword.merge(provider_opts(profile))
  end

  # The address of a model that is a map is in the map already.
  defp base_url(%__MODULE__{provider: :openai_compatible}), do: nil
  defp base_url(%__MODULE__{base_url: url}), do: url

  # Anthropic: thinking with the least effort, which answers soonest, and the
  # prompt cache on the tools, the system prompt and the last message. The
  # cache lasts one hour, because a person and not a program sets the pace.
  defp provider_opts(%__MODULE__{provider: :anthropic} = profile) do
    [
      reasoning_effort: profile.effort,
      provider_options: [
        anthropic_prompt_cache: true,
        anthropic_prompt_cache_ttl: "1h",
        anthropic_cache_messages: true
      ]
    ]
  end

  defp provider_opts(%__MODULE__{provider: :amazon_bedrock} = profile) do
    [reasoning_effort: profile.effort, provider_options: [region: profile.region]]
  end

  # Ollama cuts a prompt that is longer than its context, and says nothing.
  # So each request names the size of the context: the limit of a request.
  defp provider_opts(%__MODULE__{provider: :ollama} = profile) do
    [provider_options: [num_ctx: profile.context_tokens, keep_alive: "30m"]]
  end

  defp provider_opts(%__MODULE__{provider: :openai_compatible, api_key: nil}),
    do: [provider_options: [auth_mode: :none]]

  defp provider_opts(%__MODULE__{provider: :openai_compatible}), do: []
end
