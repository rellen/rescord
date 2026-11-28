defmodule Rescord.Ruby do
  @moduledoc """
  Ruby, the assistant of Rescord (ADR 0069). It is optional: a server with
  no provider has no Ruby.

  This domain holds the providers of the server, which a root user sets on
  a page (`Rescord.Ruby.Provider`), the code that reaches a provider
  (`Rescord.Ruby.LLM`), and the conversations of the members with their
  messages (`Rescord.Ruby.Conversation`, `Rescord.Ruby.Message`) and how
  an organisation uses Ruby (`Rescord.Ruby.Settings`), in the schema of
  each organisation.

  ## A reply

  `say/3` saves the message of a member and puts a job in the queue
  `ruby`. The job runs the tool loop of `AshAi` as that member, and writes
  the reply as it arrives (`Rescord.Ruby.Changes.Respond`): a message with
  a state, and a reason when it failed. `messages/2` reads the talk, and
  `stop_reply/2` stops the reply to a message. No page waits for Ruby: the
  job answers also when the member has closed the page.

  ## What it costs

  Each reply adds its tokens and their price to a row of
  `Rescord.Ruby.Usage`: one row for a member, a day and a model, with no
  word of a conversation. The rows stay when a conversation is deleted.
  `Rescord.Ruby.Allowance` sums a month of them against the allowance of
  the settings, and `say/3` refuses a message past it. `refusal/1` gives
  the reason of a refusal of `say/3`.

  ## The tools

  A tool is a line of `Rescord.Ruby.Catalogue`: an action tool that a
  domain declares, or a digest of `Rescord.Ruby.Digests`, which calls a
  function of a domain as the member. `Rescord.Ruby.Toolbox` makes the
  options of the loop of `AshAi` for one member: the actor of
  `Rescord.Ruby.Actor.for/1`, the names of the catalogue, and the options
  of the provider. This domain declares no tool: nothing of Ruby itself,
  and no setting, is a thing that Ruby reads.

  ## Whether Ruby is on

  Ruby is on for an organisation while its settings say so, the server
  offers their provider, and the place of that provider is the one that a
  person of the organisation agreed to (`status/1`). A change of the place
  by a root user writes nothing to an organisation: the place of the
  provider and the place of the agreement differ, and Ruby stops until a
  person with the power `settings` agrees again. `available?/2` adds the
  person: a member whose role has the power `ruby`.

  ## Who reads a conversation

  A conversation belongs to the member who started it. `conversations/1`
  and `conversation/2` are the reads of the pages of that member, and hold
  only what the actor owns. A member with the power `settings` reads the
  conversations of each member with `conversations_of/2` and
  `conversation_of/3`, and changes none. A root user who is no member of
  the organisation reads nothing: these resources have no bypass.

  No setting of Ruby is in the environment or in the application config
  (ADR 0068). The key of a provider is encrypted in `Rescord.Vault`, and
  `Rescord.Ruby.LLM` is the one module that decrypts it.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  alias Rescord.Ruby.LLM
  alias Rescord.Ruby.LLM.{Ping, Profile}
  require Ash.Query

  alias Rescord.Accounts.Checks.Granted
  alias Rescord.Accounts.User
  alias Rescord.Ruby.{Conversation, Message, Provider, Settings, Usage}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Residents, Rescord.Tasks, Rescord.Vault]
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

    resource Conversation do
      define :start_conversation, action: :start
      define :conversations, action: :mine
      define :conversation, action: :mine, get_by: [:id], not_found_error?: false
      define :rename_conversation, action: :rename, args: [:title]
      define :remove_conversation, action: :remove
      define :conversations_of, action: :of_member, args: [:owner_id]

      define :conversation_of,
        action: :of_member,
        args: [:owner_id],
        get_by: [:id],
        not_found_error?: false
    end

    resource Message do
      define :say, action: :say, args: [:conversation_id, :text]
      define :messages, action: :of_conversation, args: [:conversation_id]
      define :message, action: :read, get_by: [:id], not_found_error?: false
      define :rate_reply, action: :rate, args: [:rating]
      define :stop_reply, action: :stop
    end

    resource Settings do
      define :read_settings, action: :read, get?: true, not_found_error?: false
    end

    resource Usage
  end

  @typedoc """
  A provider as a person with the power `settings` sees it: its name and
  where the records go, and nothing of its key, its model or its prices.
  """
  @type offer :: %{
          id: String.t(),
          name: String.t(),
          kind: atom,
          place: String.t(),
          place_key: String.t(),
          default_allowance: non_neg_integer
        }

  @typedoc """
  Where Ruby stands for an organisation:

    * `:not_set_up` - the server offers no provider, and Ruby is off;
    * `:off` - an administrator has not turned it on, or turned it off;
    * `:on` - Ruby answers;
    * `{:stopped, :place}` - it is on, and the provider has another place
      than the one that an administrator agreed to;
    * `{:stopped, :provider}` - it is on, and the server does not offer
      its provider any more.
  """
  @type status :: :not_set_up | :off | :on | {:stopped, :place | :provider}

  @doc """
  The settings of an organisation, or the defaults when it has no row:
  Ruby is off. For the code of Rescord, with no person: a page reads with
  `settings_for/1`.
  """
  @spec settings(term) :: Settings.t()
  def settings(tenant) do
    case Ash.read_one!(Settings, tenant: tenant, authorize?: false) do
      nil -> %Settings{enabled: false, retention_days: 90}
      row -> row
    end
  end

  @doc """
  The settings of the organisation for the person of `opts`, or the
  defaults when it has no row. A person with no power `settings` gets
  `{:error, :forbidden}`.
  """
  @spec settings_for(keyword) :: {:ok, Settings.t()} | {:error, :forbidden}
  def settings_for(opts) do
    if can_set?(opts),
      do: {:ok, settings(Keyword.fetch!(opts, :tenant))},
      else: {:error, :forbidden}
  end

  @doc """
  Saves the settings of the organisation: the first time it makes the row,
  and then it changes it. `agreed_to` among the values is the key of the
  place that the page showed (`t:offer/0`), which an action that turns Ruby
  on needs.

  Two people who save the first settings at one moment make one row: the
  second gets an error, and saves again.
  """
  @spec save_settings(map, keyword) :: {:ok, Settings.t()} | {:error, term}
  def save_settings(values, opts) do
    case Ash.read_one!(Settings, tenant: Keyword.fetch!(opts, :tenant), authorize?: false) do
      nil -> Settings |> Ash.Changeset.for_create(:set, values, opts) |> Ash.create()
      row -> row |> Ash.Changeset.for_update(:change, values, opts) |> Ash.update()
    end
  end

  @doc """
  The providers that this server offers, as a person with the power
  `settings` sees them. Each can take a request: it is complete, and has a
  place. Any other person gets an empty list.
  """
  @spec offers(keyword) :: [offer]
  def offers(opts), do: if(can_set?(opts), do: Enum.map(offered(), &offer/1), else: [])

  @doc "Where Ruby stands for an organisation. It reads the database, and decrypts no key."
  @spec status(term) :: status
  def status(tenant) do
    settings = settings(tenant)
    offered = offered()
    provider = Enum.find(offered, &(&1.id == settings.provider_id))

    cond do
      not settings.enabled and offered == [] -> :not_set_up
      not settings.enabled -> :off
      is_nil(provider) -> {:stopped, :provider}
      not Profile.agreed?(provider, settings.agreed_destination) -> {:stopped, :place}
      true -> :on
    end
  end

  @doc """
  Whether this person can ask Ruby in this organisation: Ruby is on there
  (`status/1`), and the person is a member whose role has the power
  `ruby`. A root user gets the answer of their role as a member, and a
  root user who is no member gets `false`.

  The allowance of the month is no part of it: a member reads a
  conversation of last week also when the allowance is used.
  """
  @spec available?(term, term) :: boolean
  def available?(%User{} = user, tenant) do
    asker?(user, tenant) and status(tenant) == :on
  end

  def available?(_nobody, _tenant), do: false

  @doc "The number of organisations that have Ruby on with this provider, for the page of a root user."
  @spec organisations_with(Provider.t()) :: non_neg_integer
  def organisations_with(%Provider{id: id}) do
    Enum.count(Rescord.Repo.all_tenants(), fn tenant ->
      match?(%{enabled: true, provider_id: ^id}, settings(tenant))
    end)
  end

  # The role of the person as a member has the power `ruby`.
  defp asker?(user, tenant) do
    case Granted.role_of(user, tenant) do
      nil -> false
      role -> Rescord.Accounts.granted?(role, Conversation, :start)
    end
  end

  defp can_set?(opts),
    do: Ash.can?({Settings, :set}, opts[:actor], tenant: Keyword.fetch!(opts, :tenant))

  # The providers that an organisation can choose, by name.
  defp offered do
    Provider
    |> Ash.Query.filter(offered == true)
    |> Ash.Query.sort(:name)
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(Profile.problems(&1) == [] and is_binary(Profile.place_key(&1))))
  end

  defp offer(provider) do
    %{
      id: provider.id,
      name: provider.name,
      kind: provider.kind,
      place: Profile.place(provider),
      place_key: Profile.place_key(provider),
      default_allowance: provider.default_allowance
    }
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
  Why `say/3` refused a message, as a reason of `Rescord.Ruby.Reason`,
  from its error: `:allowance` (the allowance of the month is used),
  `:too_long` (the conversation is full) or `:rate` (too many messages of
  this person in a short time). `nil` for each other error. A page has a
  sentence for each reason.
  """
  @spec refusal(term) :: :allowance | :too_long | :rate | nil
  def refusal(%{errors: errors}) when is_list(errors), do: Enum.find_value(errors, &refusal/1)
  def refusal(%AshRateLimiter.LimitExceeded{}), do: :rate

  def refusal(%Ash.Error.Changes.InvalidAttribute{field: :text, vars: vars}) do
    case Keyword.get(List.wrap(vars), :reason) do
      reason when reason in [:allowance, :too_long] -> reason
      _other -> nil
    end
  end

  def refusal(_error), do: nil

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

  def problems(%AshRateLimiter.LimitExceeded{}),
    do: [{:text, "wait a moment before you ask again"}]

  def problems(:forbidden), do: [{nil, "You cannot do that"}]
  def problems(_error), do: [{nil, "That did not work"}]

  defp problem(%Ash.Error.Changes.Required{field: field}) when is_atom(field),
    do: [{field, required_words(field)}]

  defp problem(%Ash.Error.Forbidden.Policy{}), do: [{nil, "You cannot do that"}]
  defp problem(%AshRateLimiter.LimitExceeded{} = error), do: problems(error)

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
