defmodule Rescord.Accounts do
  @moduledoc """
  The users of Rescord, and how a user signs in.

  A person signs in with a link by email (ADR 0018). The resources of this
  domain are outside the schemas of the organisations: all organisations share
  the users.

  ## A request for a sign-in link

  `request_sign_in_link/1` starts a task and returns at once, whatever the
  address is (ADR 0019). The task looks the address up, makes the token and
  sends the email. The caller learns nothing: not whether Rescord knows the
  address, and not whether the email left. A fault goes to the log, with no
  token and no link.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Logger

  require Ash.Query

  alias Rescord.Accounts.{Grants, Member, Organisation, User}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Mail]
    # Another domain holds its own grants, and uses the check (ADR 0024).
    exports [Rescord.Accounts.Grants, Rescord.Accounts.Checks.Granted]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Accounts.User do
      define :user_by_email, action: :get_by_email, args: [:email], not_found_error?: false
      define :roots, action: :roots
      define :make_root, action: :make_root
      define :revoke_root, action: :revoke_root
    end

    resource Rescord.Accounts.Token

    resource Rescord.Accounts.Organisation do
      define :organisations, action: :read
      define :create_organisation, action: :create
      define :rename_organisation, action: :rename
      define :set_organisation_time_zone, action: :set_time_zone, args: [:time_zone]
      define :set_organisation_locale, action: :set_locale, args: [:locale]

      define :set_organisation_task_days_ahead,
        action: :set_task_days_ahead,
        args: [:task_days_ahead]

      define :set_organisation_transfer_parts,
        action: :set_transfer_parts,
        args: [:transfer_parts]

      define :set_organisation_currency, action: :set_currency, args: [:currency]

      define :authorize_export, action: :export, args: [:organisation_id]

      define :organisation_by_short_name,
        action: :by_short_name,
        args: [:short_name],
        not_found_error?: false
    end

    resource Rescord.Accounts.Member do
      define :members, action: :read
      define :member, action: :read, get_by: [:id], not_found_error?: false
      define :member_of_user, action: :read, get_by: [:user_id], not_found_error?: false
      define :invite_member, action: :invite_member, args: [:email]
      define :set_member_role, action: :set_role, args: [:role_id]
      define :invite_administrator, action: :invite_administrator, args: [:email]
      define :make_administrator, action: :make_administrator
      define :make_member, action: :make_member
      define :remove_member, action: :remove
    end

    resource Rescord.Accounts.Role do
      define :roles, action: :read, default_options: [query: [sort: [name: :asc]]]
      define :role, action: :read, get_by: [:id], not_found_error?: false
      define :define_role, action: :define
      define :revise_role, action: :revise
      define :remove_role, action: :remove
    end
  end

  @doc """
  Makes the first root user, for the email address `address`.

  A person runs this one time, in IEx, when Rescord is first deployed:

      Rescord.Accounts.bootstrap_root("you@example.com")

  It makes the user when there is none for the address. After that the person
  signs in with a link, as each user does.

  Returns `{:error, :root_exists}` when Rescord has a root user already. From
  then on, a root user makes another one.
  """
  @spec bootstrap_root(String.t()) :: {:ok, Ash.Resource.record()} | {:error, term}
  def bootstrap_root(address) when is_binary(address) do
    case roots(authorize?: false) do
      {:ok, []} ->
        User
        |> Ash.Changeset.for_create(:bootstrap_root, %{email: address})
        |> Ash.create(authorize?: false)

      {:ok, _roots} ->
        {:error, :root_exists}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Each organisation, for a job that works for all of them. It asks no
  policy: no person is there.
  """
  @spec all_organisations() :: [Ash.Resource.record()]
  def all_organisations, do: Organisation |> Ash.Query.sort(:name) |> Ash.read!(authorize?: false)

  @doc """
  The organisation of a tenant: the organisation itself, or the name of its
  schema, as an action has it. Code that asks for the local time many times
  reads the organisation one time with this.
  """
  @spec organisation_of(Ash.Resource.record() | String.t()) :: Ash.Resource.record()
  def organisation_of(%Organisation{} = organisation), do: organisation
  def organisation_of("org_" <> id), do: Ash.get!(Organisation, id, authorize?: false)

  @doc """
  The organisations that a user can open: each one for a root user, and for
  another user the ones where they are a member.

  A member is in the schema of its organisation, so this looks in each
  schema. That is one query for each organisation.
  """
  @spec organisations_for(Ash.Resource.record()) :: [Ash.Resource.record()]
  def organisations_for(%User{} = user) do
    all = Organisation |> Ash.Query.sort(:name) |> Ash.read!(authorize?: false)

    if user.root?, do: all, else: Enum.filter(all, &member_of(user, &1))
  end

  @doc """
  Opens the organisation with a short name for a user.

  Returns the organisation and the member of the user in it. A root user who
  is not a member gets `nil` for the member. Returns `:error` when there is
  no such organisation, or when the user cannot open it: the two look the
  same from outside.
  """
  @spec organisation_for(Ash.Resource.record(), term) ::
          {:ok, Ash.Resource.record(), Ash.Resource.record() | nil} | :error
  def organisation_for(%User{} = user, short_name) when is_binary(short_name) do
    with %Organisation{} = organisation <-
           organisation_by_short_name!(short_name, authorize?: false),
         member = member_of(user, organisation),
         true <- user.root? or not is_nil(member) do
      # Each line of the log of this request or page names the organisation.
      Rescord.Log.context(organisation: organisation.id)
      {:ok, organisation, member}
    else
      _no -> :error
    end
  end

  def organisation_for(_user, _short_name), do: :error

  @doc """
  What a user is in an organisation: `:root`, or the role of their member,
  a `Rescord.Accounts.Role`.
  """
  @spec role_in(Ash.Resource.record(), Ash.Resource.record() | nil) ::
          :root | Ash.Resource.record() | nil
  def role_in(%User{root?: true}, _member), do: :root
  def role_in(%User{}, %Member{role: %Rescord.Accounts.Role{} = role}), do: role
  def role_in(_user, _member), do: nil

  @doc """
  Whether a role can run an action on the members: at all, or on one member
  of the organisation `tenant`. A page asks this to decide what to show. The
  policy decides when the action runs.
  """
  @spec role_can?(term, atom, Ash.Resource.record() | nil, term) :: boolean
  def role_can?(role, action, member \\ nil, tenant \\ nil)
  def role_can?(:root, _action, _member, _tenant), do: true
  def role_can?(role, action, nil, _tenant), do: Grants.scope(role, Member, action) != :none

  def role_can?(role, action, %Member{} = member, tenant),
    do: Grants.allows?(role, Member, action, member, tenant)

  @doc "Whether a role can export the data of an organisation (ADR 0054)."
  @spec role_can_export?(term) :: boolean
  def role_can_export?(role), do: granted?(role, Organisation, :export)

  @doc "Whether a role can change the settings of an organisation."
  @spec role_can_change_settings?(term) :: boolean
  def role_can_change_settings?(role), do: granted?(role, Organisation, :set_time_zone)

  @doc """
  Whether the time zone rules know a name, for example `Australia/Brisbane`.
  """
  @spec time_zone?(term) :: boolean
  def time_zone?(zone) when is_binary(zone),
    do: match?({:ok, _now}, DateTime.now(zone, Tz.TimeZoneDatabase))

  def time_zone?(_zone), do: false

  # The locales that Rescord offers (ADR 0075), each with its name in English,
  # in the order of the names. The words of the pages are English, so each one
  # is the English of a region. `priv/localize/locales` holds the file of
  # each one, and `config :localize` names them.
  @locales [
    {"en-AU", "English (Australia)"},
    {"en-CA", "English (Canada)"},
    {"en-IN", "English (India)"},
    {"en-IE", "English (Ireland)"},
    {"en-NZ", "English (New Zealand)"},
    {"en-ZA", "English (South Africa)"},
    {"en-GB", "English (United Kingdom)"},
    {"en-US", "English (United States)"},
    {"en-001", "English (world)"}
  ]

  @default_locale "en-AU"

  @doc """
  The locales that an organisation chooses from, each as `{tag, name}`: the
  tag of BCP 47, such as `en-AU`, and its name in English (ADR 0075).

      iex> {"en-AU", "English (Australia)"} in Rescord.Accounts.locales()
      true
  """
  @spec locales() :: [{String.t(), String.t()}]
  def locales, do: @locales

  @doc "The locale of an organisation until a person chooses another."
  @spec default_locale() :: String.t()
  def default_locale, do: @default_locale

  @doc """
  Whether a tag is a locale that Rescord offers. The tag is exact: `en-AU`,
  and not `en-au`.

      iex> Rescord.Accounts.locale?("en-AU")
      true

      iex> Rescord.Accounts.locale?("fr")
      false
  """
  @spec locale?(term) :: boolean
  def locale?(tag) when is_binary(tag), do: List.keymember?(@locales, tag, 0)
  def locale?(_tag), do: false

  @doc """
  The name of a locale in English, or the tag itself for a locale that
  Rescord does not offer.

      iex> Rescord.Accounts.locale_name("en-NZ")
      "English (New Zealand)"
  """
  @spec locale_name(String.t()) :: String.t()
  def locale_name(tag) when is_binary(tag) do
    case List.keyfind(@locales, tag, 0) do
      {_tag, name} -> name
      nil -> tag
    end
  end

  @doc """
  The names of the time zones that PostgreSQL knows, for the suggestions of
  a form. `time_zone?/1` decides whether a name is valid.
  """
  @spec time_zones() :: [String.t()]
  def time_zones do
    Rescord.Repo.query!(
      "select name from pg_timezone_names where name ~ '^[A-Z][A-Za-z_]+/' and name !~ '^(posix|right)/' order by name"
    ).rows
    |> List.flatten()
    |> Enum.filter(&time_zone?/1)
  end

  # Codes of ISO 4217 that are current and that nobody pays an expense with:
  # the funds and the units of account of a state, and each code that
  # starts with X but the five currencies of a union of states. The other
  # X codes are metals, units of banks, the code for tests and the code for
  # no currency. The data of the locales marks each of these as tender.
  @not_money ~w(BOV CHE CHW CLF COU MXV USN UYI UYW)
  @money_of_a_union ~w(XAF XCD XCG XOF XPF)

  @doc """
  The currencies that an organisation chooses from (ADR 0082): each
  currency that people pay with now, as `{code, name}`, such as
  `{"AUD", "Australian Dollar"}`, in the order of the names. The names are
  English, as the words of the pages are. A fund, a metal and a unit of
  account are not in the list.
  """
  @spec currencies() :: [{String.t(), String.t()}]
  def currencies do
    case Localize.Currency.currencies_for_locale(:en, only: :current) do
      {:ok, currencies} ->
        for {code, %{name: name}} <- currencies,
            code = Atom.to_string(code),
            code not in @not_money,
            not String.starts_with?(code, "X") or code in @money_of_a_union do
          {code, name}
        end
        |> Enum.sort_by(fn {code, name} -> {String.downcase(name), code} end)

      {:error, _no_data} ->
        []
    end
  end

  @doc "Whether a text is the code of a currency of `currencies/0`, for example `AUD`."
  @spec currency?(term) :: boolean
  def currency?(code) when is_binary(code), do: List.keymember?(currencies(), code, 0)
  def currency?(_code), do: false

  @doc """
  The number of decimal places of the amounts of a currency: 2 for `AUD`,
  and 0 for `JPY`.

      iex> Rescord.Accounts.currency_digits("AUD")
      2

      iex> Rescord.Accounts.currency_digits(:JPY)
      0
  """
  @spec currency_digits(String.t() | atom) :: non_neg_integer
  def currency_digits(code) do
    case Localize.Currency.currency_for_code(code) do
      {:ok, %{digits: digits}} -> digits
      _unknown -> 2
    end
  end

  @doc """
  The code of the currency of an organisation, for example `"AUD"`. `tenant`
  is the organisation, or the name of its schema, as an action has it.
  """
  @spec currency_of(Ash.Resource.record() | String.t()) :: String.t()
  def currency_of(%Organisation{currency: currency}), do: currency
  def currency_of("org_" <> _id = schema), do: organisation_of(schema).currency

  @doc """
  The time zone of an organisation. `tenant` is the organisation, or the
  name of its schema, as an action has it.
  """
  @spec time_zone_of(Ash.Resource.record() | String.t()) :: String.t()
  def time_zone_of(%Organisation{time_zone: zone}), do: zone

  def time_zone_of("org_" <> _id = schema), do: organisation_of(schema).time_zone

  @doc "The date in an organisation at an instant: its local date."
  @spec local_date(Ash.Resource.record() | String.t(), DateTime.t()) :: Date.t()
  def local_date(tenant, %DateTime{} = instant) do
    instant
    |> DateTime.shift_zone!(time_zone_of(tenant), Tz.TimeZoneDatabase)
    |> DateTime.to_date()
  end

  @doc """
  The instant that a member gives for when a thing happened, from the text
  of a form: a local date and time in the organisation, such as
  `2026-11-16T08:30`. Returns `{:ok, nil}` for no text, which is now.

  The instant is never after now (`docs/domain.md`, section 4). A time that
  the clocks of the zone skip, or have two times, is refused: the person
  gives another minute.
  """
  @spec instant(Ash.Resource.record() | String.t(), term) ::
          {:ok, DateTime.t() | nil} | {:error, String.t()}
  def instant(_tenant, text) when text in [nil, ""], do: {:ok, nil}

  def instant(tenant, text) when is_binary(text) do
    with {:ok, instant} <- local_instant(tenant, text),
         true <- DateTime.compare(instant, DateTime.utc_now()) != :gt do
      {:ok, instant}
    else
      false -> {:error, "The time cannot be after now"}
      {:error, words} -> {:error, words}
    end
  end

  def instant(_tenant, _other),
    do: {:error, "The time is not a date and a time of this time zone"}

  @doc """
  The instant of a local date and time of an organisation, from the text of
  a form, such as `2026-11-16T08:30`. The instant can be after now: a plan
  is for the future. `instant/2` is for a thing that happened.
  """
  @spec local_instant(Ash.Resource.record() | String.t(), term) ::
          {:ok, DateTime.t()} | {:error, String.t()}
  def local_instant(tenant, text) when is_binary(text) do
    text = if String.length(text) == 16, do: text <> ":00", else: text

    with {:ok, naive} <- NaiveDateTime.from_iso8601(text),
         {:ok, local} <- DateTime.from_naive(naive, time_zone_of(tenant), Tz.TimeZoneDatabase) do
      {:ok, DateTime.shift_zone!(local, "Etc/UTC", Tz.TimeZoneDatabase)}
    else
      _not_a_time -> {:error, "The time is not a date and a time of this time zone"}
    end
  end

  def local_instant(_tenant, _other),
    do: {:error, "The time is not a date and a time of this time zone"}

  @doc """
  The instant of a date and a time of the day in an organisation. There is
  always one: for a time that the clocks skip, it is the first instant after
  the gap, and for a time that comes two times, the first one. A routine
  finds the instant of each of its tasks with this.
  """
  @spec local_instant(Ash.Resource.record() | String.t(), Date.t(), Time.t()) :: DateTime.t()
  def local_instant(tenant, %Date{} = date, %Time{} = time),
    do: instant_at(date, time, time_zone_of(tenant))

  @doc "An instant as the date and the time in an organisation."
  @spec local_time(Ash.Resource.record() | String.t(), DateTime.t()) :: DateTime.t()
  def local_time(tenant, %DateTime{} = instant),
    do: DateTime.shift_zone!(instant, time_zone_of(tenant), Tz.TimeZoneDatabase)

  @doc """
  One day of an organisation as two instants: the start of the day, and the
  start of the next day. A day with a change of the clocks is not 24 hours.
  """
  @spec day_range(Ash.Resource.record() | String.t(), Date.t()) :: {DateTime.t(), DateTime.t()}
  def day_range(tenant, %Date{} = date) do
    zone = time_zone_of(tenant)
    {start_of_day(date, zone), start_of_day(Date.add(date, 1), zone)}
  end

  # The first instant of a date in a zone. When the clocks skip midnight, it
  # is the first time after the gap, and when midnight comes two times, the
  # first one.
  defp start_of_day(date, zone), do: instant_at(date, ~T[00:00:00], zone)

  defp instant_at(date, time, zone) do
    case DateTime.new(date, time, zone, Tz.TimeZoneDatabase) do
      {:ok, local} -> local
      {:ambiguous, first, _second} -> first
      {:gap, _before, later} -> later
    end
    |> DateTime.shift_zone!("Etc/UTC", Tz.TimeZoneDatabase)
  end

  @doc "The date in an organisation now."
  @spec today(Ash.Resource.record() | String.t()) :: Date.t()
  def today(tenant), do: local_date(tenant, DateTime.utc_now())

  @doc """
  Whether a role can run an action of a resource at all. Another domain asks
  this about a resource of its own, to decide what a page shows. The policy
  decides when the action runs.
  """
  @spec granted?(term, module, atom) :: boolean
  def granted?(:root, _resource, _action), do: true
  def granted?(role, resource, action), do: Grants.scope(role, resource, action) != :none

  @doc "The messages of an error of an action, for a person to read."
  @spec error_messages(term) :: [String.t()]
  def error_messages(%{errors: errors}) when is_list(errors) do
    Enum.flat_map(errors, fn
      %{field: field, message: message} = error when not is_nil(field) and is_binary(message) ->
        ["#{field_words(field)} #{with_values(message, Map.get(error, :vars))}"]

      # A validation that runs in a hook of the action names its field in a list.
      %{fields: [field | _], message: message} = error when is_binary(message) ->
        ["#{field_words(field)} #{with_values(message, Map.get(error, :vars))}"]

      # An error of a hook in the transaction holds the errors of the action.
      %{errors: [_ | _]} = inner ->
        error_messages(inner)

      error ->
        [message(error)]
    end)
  end

  def error_messages(_error), do: ["That did not work"]

  defp message(error) do
    case error do
      # A value that is necessary and is not there has no message of its own.
      %Ash.Error.Changes.Required{field: field} when not is_nil(field) ->
        "#{field_words(field)} is required"

      %Ash.Error.Forbidden.Policy{} ->
        "You cannot do that"

      # The record changed after the page read it.
      %Ash.Error.Changes.StaleRecord{} ->
        "Somebody changed this a moment ago. The page shows it as it is now"

      error ->
        Exception.message(error)
    end
  end

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

  # A list is not text here: `to_string/1` reads a list of numbers as letters.
  defp value_words(value) when is_binary(value), do: value
  defp value_words(value) when is_number(value) or is_atom(value), do: to_string(value)
  defp value_words(value), do: inspect(value)

  # `:arrived_on` reads `Arrived on`, and `:kind_id` reads `Kind`.
  defp field_words(field) do
    field
    |> to_string()
    |> String.replace_suffix("_id", "")
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp member_of(%User{id: user_id}, %Organisation{} = organisation) do
    Member
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.load(:role)
    |> Ash.read_one!(tenant: organisation, authorize?: false)
  end

  @sign_in_tasks Rescord.Accounts.SignInTasks

  @doc "The name of the supervisor of the tasks that `request_sign_in_link/1` starts."
  def sign_in_tasks, do: @sign_in_tasks

  @doc """
  Asks for a sign-in link for an email address. Returns `:ok` at once.

  The work happens in a task, and its result does not come back (ADR 0019).
  `address` is whatever the person typed: this function does not look at it.

  Returns `{:error, :busy}` when too many requests are in progress. That
  depends on the load only, and never on the address.
  """
  @spec request_sign_in_link(term) :: :ok | {:error, :busy}
  def request_sign_in_link(address) do
    case Task.Supervisor.start_child(@sign_in_tasks, fn -> send_sign_in_link(address) end) do
      {:ok, _pid} -> :ok
      {:error, :max_children} -> {:error, :busy}
    end
  end

  # Runs in the task. Nothing that it learns goes back to the person who asked.
  defp send_sign_in_link(address) when is_binary(address) do
    strategy = AshAuthentication.Info.strategy!(User, :magic_link)

    case AshAuthentication.Strategy.action(strategy, :request, %{"email" => address}) do
      :ok -> :ok
      {:error, error} -> log_fault(error)
    end
  rescue
    error -> log_fault(error)
  catch
    kind, _reason -> Logger.warning("A request for a sign-in link stopped: #{kind}")
  end

  defp send_sign_in_link(_address), do: :ok

  # The message of an error can hold the address, a token or a link, so the
  # log names only the kind of the error (`Rescord.Log.reason/1`).
  defp log_fault(%Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{} | _]}) do
    Logger.info("A request for a sign-in link was over the limit of its address")
  end

  defp log_fault(error) do
    Logger.warning("A request for a sign-in link failed: #{Rescord.Log.reason(error)}")
  end

  @doc """
  Signs a person in with the token of a sign-in link.

  Returns the user with a session token in its metadata, or `:error`. A token
  works one time, for 15 minutes.
  """
  @spec sign_in_with_link(term) :: {:ok, Ash.Resource.record()} | :error
  def sign_in_with_link(token) when is_binary(token) do
    strategy = AshAuthentication.Info.strategy!(User, :magic_link)

    case AshAuthentication.Strategy.action(strategy, :sign_in, %{"token" => token}) do
      {:ok, %User{} = user} -> {:ok, user}
      _other -> :error
    end
  rescue
    _error -> :error
  end

  def sign_in_with_link(_token), do: :error
end
