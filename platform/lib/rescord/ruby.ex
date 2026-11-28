defmodule Rescord.Ruby do
  @moduledoc """
  Ruby, the assistant of Rescord (ADR 0069). It is optional: a server with
  no provider has no Ruby.

  This domain holds the providers of the server, which a root user sets on
  a page (`Rescord.Ruby.Provider`), and the code that reaches a provider
  (`Rescord.Ruby.LLM`). The conversations, the tools and the settings of
  an organisation come with the later steps of the work.

  No setting of Ruby is in the environment or in the application config
  (ADR 0068). The key of a provider is encrypted in `Rescord.Vault`, and
  `Rescord.Ruby.LLM` is the one module that decrypts it.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  alias Rescord.Ruby.LLM
  alias Rescord.Ruby.LLM.{Ping, Profile}
  alias Rescord.Ruby.Provider

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Vault]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Provider do
      define :providers, action: :read
      define :provider, action: :read, get_by: [:id], not_found_error?: false
      define :add_provider, action: :add
      define :change_provider, action: :change
      define :set_provider_key, action: :set_key, args: [:api_key]
      define :remove_provider, action: :remove
    end
  end

  @doc "The kinds of a provider: the services that Rescord can reach."
  @spec provider_kinds() :: [atom]
  def provider_kinds, do: Profile.kinds()

  @doc """
  The values that a provider of this kind has when the root user gives
  none. The form of the page shows them in its fields.
  """
  @spec provider_defaults(atom) :: map
  def provider_defaults(kind), do: Profile.defaults(kind)

  @doc """
  Where the records of a question go with this provider, in the words that
  an administrator of an organisation reads. It takes a provider, or the
  values of a form, and needs no key.
  """
  @spec place(map) :: String.t()
  def place(provider), do: Profile.place(provider)

  @doc "Whether Rescord has the prices of this model, so that the provider needs none."
  @spec priced?(String.t() | nil) :: boolean
  def priced?(model), do: is_binary(model) and LLM.Cost.prices(model) != nil

  @doc """
  What is wrong with a saved provider, by field: a key that is not there
  for a kind that takes one, a value that no longer fits its rule. An
  empty list when a request can go. It decrypts nothing.
  """
  @spec provider_problems(Provider.t()) :: [Profile.problem()]
  def provider_problems(%Provider{} = provider), do: Profile.problems(provider)

  @doc """
  Whether this server has a provider. Rescord asks at its start, with no
  person, and loads the model catalogue of the library when it has one.
  """
  @spec any_provider?() :: boolean
  def any_provider?, do: Ash.exists?(Provider, authorize?: false)

  @doc """
  Saves the fields of a provider, and its key when `key` is a text, for
  the form of the page. They are two actions, so that the history says
  that a key was set and nothing else, and one transaction: a key that is
  refused leaves the fields as they were.
  """
  @spec save_provider(Provider.t(), map, String.t() | nil, keyword) ::
          {:ok, Provider.t()} | {:error, term}
  def save_provider(%Provider{} = provider, attributes, key, opts \\ []) do
    Ash.transact([Provider], fn ->
      with {:ok, provider} <- change_provider(provider, attributes, opts) do
        if is_binary(key), do: set_provider_key(provider, key, opts), else: {:ok, provider}
      end
    end)
    |> case do
      {:ok, {:ok, provider}} -> {:ok, provider}
      {:ok, {:error, error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Loads the model catalogue of the library that reaches a provider, when
  this server has a provider. The first use of the catalogue takes some
  seconds, and without this the first question after a start waits for it.

  Rescord runs it one time, in a task of its own, when it starts. A server
  with no provider loads nothing. A fault here costs only that wait, so it
  stops nothing: the task ends.
  """
  @spec warm_up() :: :ok
  def warm_up do
    if any_provider?(), do: ReqLLM.model("anthropic:claude-opus-5-5")
    :ok
  rescue
    # The database of a new server has no table yet.
    _error -> :ok
  end

  @doc """
  The providers, for `bin/check`, which runs with no person. A row holds
  no key that can be read: the key stays encrypted.
  """
  @spec providers_for_check() :: [Provider.t()]
  def providers_for_check do
    Provider |> Ash.Query.sort(:inserted_at) |> Ash.read!(authorize?: false)
  end

  @doc """
  Sends one small request with the saved provider, and writes what it
  found: `:ok`, or a reason of `Rescord.Ruby.Reason`. Only a root user
  runs it, because it spends money of the person who has the account.

  The request holds the word "ping" and nothing of a rescue. The result
  never holds the error of the service, which can hold its answer.
  """
  @spec test_provider(Provider.t(), keyword) :: {:ok, Provider.t()} | {:error, term}
  def test_provider(%Provider{} = provider, opts \\ []) do
    # The policy of `note_test` lets a root user through, and nobody else.
    # It is asked before the request, so nobody else spends anything.
    if Ash.can?({provider, :note_test}, opts[:actor]) do
      result =
        case LLM.profile_of(provider) do
          {:ok, profile} -> Ping.run(profile).outcome
          # No profile, and so no request: the vault cannot open the key,
          # or the row has no key.
          {:error, :key_refused} -> {:error, :key_refused}
          {:error, problems} -> {:error, no_profile(problems)}
        end

      result =
        case result do
          :ok -> :ok
          {:error, reason} -> reason
        end

      provider
      |> Ash.Changeset.for_update(
        :note_test,
        %{tested_at: DateTime.utc_now(), test_result: result},
        opts
      )
      |> Ash.update()
    else
      {:error, :forbidden}
    end
  end

  # A row that a request cannot use: without its key, the reason is the
  # key. Any other value that no longer fits its rule has no reason of its
  # own, and the sentence of `:unknown` says to check each field.
  defp no_profile(problems) do
    if List.keymember?(problems, :api_key, 0), do: :key_refused, else: :unknown
  end

  @doc """
  The problems of an error of an action, each with its field, in words for
  a person. A problem with no field has `nil`. The page of a provider puts
  each one beside its field.
  """
  @spec problems(term) :: [{atom | nil, String.t()}]
  def problems(%{errors: errors}) when is_list(errors) do
    errors
    |> Enum.flat_map(&problem/1)
    |> Enum.map(fn
      # The words of the type name each kind as the code names it.
      {:kind, _words} -> {:kind, "choose the service"}
      problem -> problem
    end)
    |> Enum.uniq()
  end

  def problems(:forbidden), do: [{nil, "You cannot do that"}]
  def problems(_error), do: [{nil, "That did not work"}]

  defp problem(%Ash.Error.Changes.Required{field: field}) when is_atom(field),
    do: [{field, required_words(field)}]

  defp problem(%Ash.Error.Forbidden.Policy{}), do: [{nil, "You cannot do that"}]

  defp problem(%Ash.Error.Changes.StaleRecord{}),
    do: [{nil, "Somebody changed this a moment ago. The page shows it as it is now"}]

  defp problem(%{field: field, message: message} = error)
       when is_atom(field) and not is_nil(field) and is_binary(message),
       do: [{field, with_values(message, Map.get(error, :vars))}]

  defp problem(%{fields: [field | _], message: message} = error)
       when is_atom(field) and is_binary(message),
       do: [{field, with_values(message, Map.get(error, :vars))}]

  # An error of a hook in the transaction holds the errors of the action.
  defp problem(%{errors: [_ | _]} = inner), do: problems(inner)
  defp problem(_other), do: [{nil, "That did not work"}]

  defp required_words(:kind), do: "choose the service"
  defp required_words(:name), do: "give the provider a name"
  defp required_words(:model), do: "name the model"
  defp required_words(:api_key), do: "type the key"
  defp required_words(_field), do: "is required"

  # A message of Ash can name a value of the rule, as in `must be more than
  # or equal to %{min}`. The values are beside the message.
  defp with_values(message, values) when is_list(values) or is_map(values) do
    Enum.reduce(values, message, fn
      {key, value}, text when is_atom(key) or is_binary(key) ->
        String.replace(text, "%{#{key}}", value_words(value))

      _other, text ->
        text
    end)
  end

  defp with_values(message, _values), do: message

  defp value_words(value) when is_binary(value), do: value
  defp value_words(value) when is_number(value) or is_atom(value), do: to_string(value)
  defp value_words(value), do: inspect(value)
end
