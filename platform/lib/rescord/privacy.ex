defmodule Rescord.Privacy do
  @moduledoc """
  The erasure of a member on request, the requests themselves and the
  settings of privacy of an organisation (ADR 0105, issue 31).

  ## Two scopes

    * **In one organisation.** A member with the power `privacy` erases a
      member or a former member there, with `erase/3`, from a request
      (`Rescord.Privacy.Request`). It reaches the schema of that
      organisation. When the person then has no membership left in any
      organisation and is not a root user, the account is erased too.
    * **Of the account.** A root user erases the account, with
      `erase_account/3`, which pseudonymises the person in each
      organisation where they were ever a member.

  ## What an erasure does

  One transaction, under one correlation id (ADR 0101), which the request
  keeps:

    * the member is removed if they were a member, as `remove` does: the
      tasks and routines that are open let go of them, and their calendar
      feeds stop;
    * the member row gets "Former member N" (`Rescord.Accounts.Member`),
      and holds the email for the money records while an expense younger
      than the money period names the person;
    * the member row emits `:member_erased`: the conversations with Ruby
      go, and each calendar feed is renamed "Feed of former member N", with
      the old name redacted in its versions;
    * with no membership left, the account: each token goes, the email
      goes from the user and from its versions (`Rescord.Redaction`), and
      each job whose arguments hold the email goes;
    * the request is done, and keeps what was kept and why;
    * a job sends the person the email of `Rescord.Mail.erasure_done/4`,
      unless the request came by letter.

  After the commit, a marker goes to the store for each erased member
  (`marker_key/2`), so that `Rescord.Release.reapply_erasures/0` erases
  the person again after the restore of an older dump. The marker holds
  ids, a number and a date, and no email.

  The records that members wrote about the animals stay, under the name
  Former member N: the care of each animal depends on them. Rescord calls
  this pseudonymisation, and never anonymous: the ids stay.

  ## Who erases

  A member with the power `privacy` erases a member whose role has neither
  `privacy` nor `members`; only a root user erases one whose role has
  either (`erasable?/3`). No role has a grant for the actions `erase` of
  the accounts: this domain runs them, after its own check.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Logger

  alias Rescord.{Accounts, Correlation, Expenses, Redaction, Repo, Storage}
  alias Rescord.Privacy.{InstanceSettings, Request, Settings}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true

    deps [
      Rescord,
      Rescord.Accounts,
      Rescord.Expenses,
      Rescord.Mail,
      Rescord.Notifications,
      Rescord.Vault
    ]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Request do
      define :requests, action: :read, default_options: [query: [sort: [received_on: :desc]]]
      define :open_requests, action: :open
      define :request, action: :read, get_by: [:id], not_found_error?: false
      define :ask, action: :ask
      define :record_request, action: :record
      define :extend_request, action: :extend
      define :refuse_request, action: :refuse
      define :withdraw_request, action: :withdraw
      define :note_told, action: :note_told, args: [:told_on]
    end

    resource Settings do
      define :read_settings, action: :read
      define :set_settings, action: :set
      define :change_settings, action: :change
    end

    resource InstanceSettings do
      define :read_instance_settings, action: :read
      define :set_instance_settings, action: :set
      define :change_instance_settings, action: :change
    end
  end

  @typedoc """
  What a person chose on the page of an erasure: whether the comments of
  the person stay, signed Former member N, and what else the organisation
  keeps and why, in their own words.
  """
  @type choices :: %{optional(:keep_comments) => boolean, optional(:kept) => String.t() | nil}

  @doc """
  The settings of privacy of the organisation `tenant`: its row, or the
  start values when it has none. It reads with no actor: each setting says
  how long the organisation keeps what, and none is a secret.
  """
  @spec settings(term) :: Settings.t()
  def settings(tenant) do
    case read_settings(tenant: tenant, authorize?: false) do
      {:ok, [settings | _]} ->
        settings

      {:ok, []} ->
        struct(Settings, Map.new(Ash.Resource.Info.attributes(Settings), &{&1.name, default(&1)}))
    end
  end

  defp default(%{default: default}) when is_function(default, 0), do: default.()
  defp default(%{default: default}), do: default

  @doc """
  Saves the settings of privacy, as the actor of `options`: the first row,
  or a change of the row.
  """
  @spec save_settings(map, keyword) :: {:ok, Settings.t()} | {:error, term}
  def save_settings(params, options) do
    case read_settings(options) do
      {:ok, [settings | _]} -> change_settings(settings, params, options)
      {:ok, []} -> set_settings(params, options)
      error -> error
    end
  end

  @doc """
  The settings of privacy of the server (`Rescord.Privacy.InstanceSettings`):
  its row, or the start values when it has none.
  """
  @spec instance_settings() :: InstanceSettings.t()
  def instance_settings do
    case read_instance_settings(authorize?: false) do
      {:ok, [settings | _]} ->
        settings

      {:ok, []} ->
        struct(
          InstanceSettings,
          Map.new(Ash.Resource.Info.attributes(InstanceSettings), &{&1.name, default(&1)})
        )
    end
  end

  @doc "Saves the settings of privacy of the server, as the root user of `options`."
  @spec save_instance_settings(map, keyword) :: {:ok, InstanceSettings.t()} | {:error, term}
  def save_instance_settings(params, options) do
    case read_instance_settings(options) do
      {:ok, [settings | _]} -> change_instance_settings(settings, params, options)
      {:ok, []} -> set_instance_settings(params, options)
      error -> error
    end
  end

  @doc """
  What the privacy notice of the organisation with the random id
  `notice_id` says, or `:error` for an id that names none. `missing` names
  each blank that the notice needs and that nobody filled: the notice
  does not show until it is empty.
  """
  @spec notice(String.t()) :: {:ok, map} | :error
  def notice(notice_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(notice_id),
         {:ok, %{} = organisation} <-
           Accounts.organisation_by_notice_id(notice_id, authorize?: false) do
      settings = settings(organisation)
      server = instance_settings()

      missing =
        for {field, value} <- [
              contact: settings.contact_email,
              operator: server.operator_name,
              hosting: server.hosting,
              mail: server.mail_provider
            ],
            value in [nil, ""],
            do: field

      {:ok, %{organisation: organisation, settings: settings, server: server, missing: missing}}
    else
      _none -> :error
    end
  end

  @doc """
  Whether a role can run an action of privacy at all: an action of a
  request, or `:change_settings`. A page asks this to decide what to show,
  and the policy decides when the action runs.
  """
  @spec role_can?(term, atom) :: boolean
  def role_can?(role, :change_settings), do: Accounts.granted?(role, Settings, :change)
  def role_can?(role, action), do: Accounts.granted?(role, Request, action)

  @doc """
  Whether the actor of `options` may erase the member `member` in the
  organisation of `options`. A root user may erase each member who is not
  a root user. A person whose role has the power `privacy` may erase a
  member whose role has neither `privacy` nor `members`, so that two
  administrators cannot erase each other.
  """
  @spec erasable?(Ash.Resource.record(), keyword) :: boolean
  def erasable?(member, options) do
    actor = Keyword.fetch!(options, :actor)
    tenant = Keyword.fetch!(options, :tenant)

    cond do
      not is_nil(member.erased_at) -> false
      actor_root?(actor) -> true
      not Accounts.power?(actor, tenant, :privacy) -> false
      true -> not manager?(member, tenant)
    end
  end

  defp actor_root?(%{root?: true}), do: true
  defp actor_root?(_actor), do: false

  defp manager?(member, tenant) do
    case Accounts.role(member.role_id, tenant: tenant, authorize?: false) do
      {:ok, %{powers: powers}} -> Enum.any?([:privacy, :members], &(&1 in powers))
      _none -> false
    end
  end

  @doc """
  The day until which the money records of the organisation `tenant` hold
  the email of the user `user_id`: the last day that an expense names the
  user, plus the years of the money period. `nil` when no expense names
  the user, or when that day has passed.
  """
  @spec hold_until(Ecto.UUID.t(), term) :: Date.t() | nil
  def hold_until(user_id, tenant) do
    with %Date{} = last <- Expenses.last_day_naming(user_id, tenant),
         until = Date.shift(last, year: settings(tenant).money_years),
         true <- Date.compare(until, Accounts.today(tenant)) != :lt do
      until
    else
      _no_hold -> nil
    end
  end

  @doc """
  Erases the member of the request `request` in the organisation of
  `options`, as the actor of `options`, with the `choices` of the page.
  Returns the request, done. See the moduledoc for what it does.
  """
  @spec erase(Request.t(), choices, keyword) :: {:ok, Request.t()} | {:error, term}
  def erase(%Request{} = request, choices, options) do
    tenant = Keyword.fetch!(options, :tenant)
    options = Correlation.start(options)

    with :ok <- received(request),
         {:ok, member} <- member_of(request, tenant),
         :ok <- may_erase(member, options) do
      keep_comments = Map.get(choices, :keep_comments, false) == true

      result =
        transact(fn ->
          with {:ok, done, markers} <-
                 do_erase(request, member, keep_comments, choices[:kept], options),
               do: {:ok, {done, markers}}
        end)

      with {:ok, {done, markers}} <- result do
        Enum.each(markers, &write_marker/1)
        {:ok, done}
      end
    end
  end

  # One transaction for each action of an erasure. Ash sends the
  # notifications of the actions after the commit, and takes each change
  # back when the function returns an error.
  defp transact(function) do
    case Ash.transact(Request, function) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  defp received(%{state: :received}), do: :ok
  defp received(_request), do: {:error, :closed}

  defp member_of(request, tenant) do
    case Accounts.member_with_former(request.member_id, tenant: tenant, authorize?: false) do
      {:ok, %{} = member} -> {:ok, member}
      _none -> {:error, :not_found}
    end
  end

  defp may_erase(member, options) do
    if erasable?(member, options), do: :ok, else: {:error, :forbidden}
  end

  defp do_erase(request, member, keep_comments, kept_words, options) do
    tenant = Keyword.fetch!(options, :tenant)
    internal = internal(options)
    user = user!(member.user_id)
    to = request_address(request, user, tenant)

    with {:ok, member} <- remove_if_member(member, internal),
         {:ok, erased} <- pseudonymise(member, user, keep_comments, internal),
         {:ok, account_markers} <- erase_account_if_alone(user, keep_comments, options) do
      kept = kept(erased, kept_words)

      with {:ok, done} <-
             request
             |> Ash.Changeset.for_update(
               :complete,
               %{
                 kept: kept,
                 keep_comments: keep_comments,
                 former_number: erased.former_number,
                 correlation_id: correlation_id(options)
               },
               internal
             )
             |> Ash.update(),
           :ok <- tell(done, to, erased, kept, tenant) do
        {:ok, done, [marker(tenant, erased, user) | account_markers]}
      end
    end
  end

  # The actions that the erasure runs, after its own check: with the actor
  # and the correlation id of the erasure, and with no policy.
  defp internal(options),
    do: Keyword.take(options, [:actor, :tenant, :context]) ++ [authorize?: false]

  defp user!(user_id), do: Ash.get!(Accounts.User, user_id, authorize?: false)

  defp request_address(%{how_received: :letter}, _user, _tenant), do: nil

  defp request_address(request, user, tenant) do
    contact =
      request
      |> Ash.load!(:contact, tenant: tenant, authorize?: false)
      |> Map.get(:contact)

    if is_binary(contact) and String.contains?(contact, "@"),
      do: contact,
      else: user.email && to_string(user.email)
  end

  defp remove_if_member(%{archived_at: nil} = member, internal) do
    with :ok <- Accounts.remove_member(member, internal) do
      Accounts.member_with_former(member.id, internal)
    end
  end

  defp remove_if_member(member, _internal), do: {:ok, member}

  defp pseudonymise(member, user, keep_comments, internal) do
    tenant = Keyword.fetch!(internal, :tenant)
    until = hold_until(member.user_id, tenant)

    hold =
      if until && user.email,
        do: %{held_email: to_string(user.email), held_until: until},
        else: %{}

    Accounts.erase_member(member, Map.put(hold, :keep_comments, keep_comments), internal)
  end

  defp kept(erased, words) do
    hold =
      if erased.held_until,
        do:
          "Your email address stays on the money records until #{Calendar.strftime(erased.held_until, "%-d %B %Y")}, because the law asks us to keep them.",
        else: "We keep no record with your email address."

    case words && String.trim(words) do
      empty when empty in [nil, ""] -> hold
      words -> hold <> " " <> words
    end
  end

  defp correlation_id(options),
    do: get_in(options, [:context, :shared, :ash_paper_trail, :operation_id])

  # The email of the outcome goes in a job, in the transaction: the job is
  # there only when the erasure is. Its arguments hold the address until the
  # pruner of Oban deletes the job, one day after the send.
  defp tell(_request, nil, _erased, _kept, _tenant), do: :ok

  defp tell(request, to, erased, kept, tenant) do
    organisation = Accounts.organisation_of(tenant)

    %{
      to: to,
      organisation: organisation.name,
      label: "Former member #{erased.former_number}",
      kept: kept,
      request_id: request.id,
      tenant: tenant_name(tenant)
    }
    |> Rescord.Privacy.Workers.SendErasureDone.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      error -> error
    end
  end

  defp tenant_name("org_" <> _ = tenant), do: tenant
  defp tenant_name(%{id: id}), do: "org_" <> id

  # The account goes when the person is a member of no organisation and is
  # no root user (issue 31, call 2). Each organisation where the person was
  # a former member, and is not erased, pseudonymises them too, so that no
  # page shows an empty email.
  defp erase_account_if_alone(%{root?: true}, _keep_comments, _options), do: {:ok, []}

  defp erase_account_if_alone(user, keep_comments, options) do
    if Accounts.memberships(user.id) == [],
      do: erase_account_data(user, keep_comments, Keyword.delete(options, :tenant)),
      else: {:ok, []}
  end

  @doc """
  Erases the account of the user `user`, as the root user of `options`
  (ADR 0105): the person is pseudonymised in each organisation where they
  were a member, and the account loses its email and its tokens. Each
  organisation gets a closed request that says so. `keep_comments` is the
  choice of the root user for every organisation (issue 31, call 7).
  """
  @spec erase_account(Accounts.User.t(), choices, keyword) :: :ok | {:error, term}
  def erase_account(user, choices, options) do
    options = Correlation.start(options)
    line = account_line(choices)
    options = Keyword.put(options, :account_line, line)

    cond do
      not actor_root?(Keyword.get(options, :actor)) ->
        {:error, :forbidden}

      user.root? ->
        {:error, :root}

      not is_nil(user.erased_at) ->
        {:error, :closed}

      true ->
        keep_comments = Map.get(choices, :keep_comments, false) == true

        result =
          transact(fn ->
            with {:ok, markers} <- remove_everywhere(user, options),
                 {:ok, more} <- erase_account_data(user, keep_comments, options),
                 do: {:ok, markers ++ more}
          end)

        with {:ok, markers} <- result do
          Enum.each(markers, &write_marker/1)
          :ok
        end
    end
  end

  # An account erasure removes the person from each organisation first.
  defp remove_everywhere(user, options) do
    user.id
    |> Accounts.memberships()
    |> Enum.reduce_while({:ok, []}, fn {tenant, member}, ok ->
      case Accounts.remove_member(member, internal(Keyword.put(options, :tenant, tenant))) do
        :ok -> {:cont, ok}
        error -> {:halt, error}
      end
    end)
  end

  defp erase_account_data(user, keep_comments, options) do
    with {:ok, markers} <- pseudonymise_elsewhere(user, keep_comments, options),
         :ok <- forget_account(user, options) do
      {:ok, markers}
    end
  end

  # Each organisation where the person is a former member who is not
  # erased: an erasure there, with a closed request of its own.
  defp pseudonymise_elsewhere(user, keep_comments, options) do
    user.id
    |> Accounts.former_memberships()
    |> Enum.reduce_while({:ok, []}, fn {tenant, member}, {:ok, markers} ->
      internal = internal(Keyword.put(options, :tenant, tenant))

      with {:ok, erased} <- pseudonymise(member, user, keep_comments, internal),
           {:ok, _request} <-
             account_request(erased, keep_comments, internal, options[:account_line]) do
        {:cont, {:ok, [marker(tenant, erased, user) | markers]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  # How the request to the operator came, for the closed line of each
  # organisation.
  defp account_line(choices) do
    how = Map.get(choices, :how_received)
    identity = Map.get(choices, :identity)

    [
      "Erasure of the account by a root user",
      how && "asked #{how |> to_string() |> String.replace("_", " ")}",
      identity
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("; ")
    |> String.slice(0, 300)
  end

  defp account_request(erased, keep_comments, internal, line) do
    Request
    |> Ash.Changeset.for_create(
      :closed,
      %{
        member_id: erased.id,
        how_received: :account,
        identity: line || "Erasure of the account by a root user",
        kept: kept(erased, nil),
        keep_comments: keep_comments,
        former_number: erased.former_number,
        correlation_id: correlation_id(internal)
      },
      internal
    )
    |> Ash.create()
  end

  defp forget_account(user, options) do
    internal = internal(Keyword.delete(options, :tenant))
    email = to_string(user.email)

    with {:ok, _user} <- Accounts.erase_user(user, internal) do
      Accounts.delete_tokens(user.id)
      Rescord.Notifications.forget_user(user.id)
      Redaction.redact_versions(Accounts.User, [user.id], [:email], nil)
      delete_jobs_naming(email)
      :ok
    end
  end

  # Each job that waits and whose arguments hold the email: an invitation,
  # a sign-in link. A job that runs now finishes.
  defp delete_jobs_naming(email) do
    Repo.query!(
      """
      DELETE FROM oban_jobs
      WHERE state <> 'executing' AND strpos(lower(args::text), lower($1)) > 0
      """,
      [email]
    )
  end

  @doc """
  The requests that wait, for the page of what needs attention (ADR 0065):
  each request that is received and not done, the first due first, for a
  role with the power `privacy`. Each row has the day that it is due.
  """
  @spec attention(term, keyword) :: {:ok, %{rows: [map], total: non_neg_integer}} | {:error, term}
  def attention(role, opts) do
    {limit, opts} = Keyword.pop(opts, :limit, 8)
    opts = Keyword.take(opts, [:actor, :tenant])

    if Accounts.granted?(role, Request, :extend) do
      with {:ok, requests} <- open_requests(opts) do
        rows =
          for request <- Enum.take(requests, limit),
              do: %{
                kind: :erasure_request,
                record: request,
                due: request.extended_to || request.due_on
              }

        {:ok, %{rows: rows, total: length(requests)}}
      end
    else
      {:ok, %{rows: [], total: 0}}
    end
  end

  @doc """
  The daily work of privacy in the organisation `tenant` (ADR 0105), which
  `Rescord.Privacy.Workers.Daily` runs:

    * each hold of the money records that ended lets go of the email;
    * each closed request older than the years of the settings goes;
    * when the settings say so, each former member who left longer ago
      than their months is pseudonymised, with a closed line of its own
      (issue 31, call 9): nobody asked, so it is no request.

  Returns the counts.
  """
  @spec daily(term) :: %{
          released: non_neg_integer,
          forgotten: non_neg_integer,
          pseudonymised: non_neg_integer
        }
  def daily(tenant) do
    settings = settings(tenant)
    today = Accounts.today(tenant)
    options = [tenant: tenant, authorize?: false]

    released =
      for member <- Accounts.holds_ended_before!(today, options),
          match?({:ok, _member}, Accounts.release_hold(member, options)),
          reduce: 0,
          do: (count -> count + 1)

    before = DateTime.shift(DateTime.utc_now(), year: -settings.closed_request_years)

    forgotten =
      for request <-
            Ash.read!(Ash.Query.for_read(Request, :closed_before, %{before: before}), options),
          Ash.destroy(request, Keyword.put(options, :action, :forget)) == :ok,
          reduce: 0,
          do: (count -> count + 1)

    %{
      released: released,
      forgotten: forgotten,
      pseudonymised: pseudonymise_after(settings, tenant)
    }
  end

  defp pseudonymise_after(%{pseudonymise_after_months: nil}, _tenant), do: 0

  defp pseudonymise_after(%{pseudonymise_after_months: months}, tenant) do
    left_before = DateTime.shift(DateTime.utc_now(), month: -months)

    for member <- Accounts.former_members(tenant: tenant, authorize?: false),
        DateTime.before?(member.archived_at, left_before),
        pseudonymise_alone(member, tenant) == :ok,
        reduce: 0,
        do: (count -> count + 1)
  end

  # The comments stay: nobody asked to delete them.
  defp pseudonymise_alone(member, tenant) do
    options = Correlation.start(tenant: tenant, authorize?: false)
    user = user!(member.user_id)

    result =
      transact(fn ->
        with {:ok, erased} <- pseudonymise(member, user, true, internal(options)),
             {:ok, _line} <-
               Request
               |> Ash.Changeset.for_create(
                 :closed,
                 %{
                   member_id: erased.id,
                   how_received: :automatic,
                   identity: "The months of the settings of privacy",
                   kept: kept(erased, nil),
                   keep_comments: true,
                   former_number: erased.former_number,
                   correlation_id: correlation_id(options)
                 },
                 internal(options)
               )
               |> Ash.create(),
             {:ok, markers} <- erase_account_if_alone(user, true, options) do
          {:ok, [marker(tenant, erased, user) | markers]}
        end
      end)

    with {:ok, markers} <- result do
      Enum.each(markers, &write_marker/1)
      :ok
    end
  end

  @doc """
  The key in the store of the marker of the erased member `member_id` of
  the organisation `organisation_id`.
  """
  @spec marker_key(String.t(), String.t()) :: Storage.key()
  def marker_key(organisation_id, member_id),
    do: Storage.key(organisation_id, ["erasures", member_id])

  defp marker("org_" <> organisation_id, erased, user),
    do: marker(organisation_id, erased, user)

  defp marker(%{id: organisation_id}, erased, user), do: marker(organisation_id, erased, user)

  defp marker(organisation_id, erased, user) when is_binary(organisation_id) do
    %{
      key: marker_key(organisation_id, erased.id),
      body: %{
        "organisation_id" => organisation_id,
        "member_id" => erased.id,
        "user_id" => user.id,
        "former_number" => erased.former_number,
        "erased_on" => Date.to_iso8601(DateTime.to_date(erased.erased_at))
      }
    }
  end

  # A marker that cannot be written leaves the erasure as it is: the
  # comparison of the store (`bin/check-files`) names it as missing, and
  # `reapply_erasures/0` writes it again.
  defp write_marker(%{key: key, body: body}) do
    case Storage.put(key, Jason.encode!(body), "application/json") do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "The marker of an erasure was not written: #{Storage.reason_words(reason)}"
        )
    end
  end

  @doc """
  The keys of the markers that the erased members of the organisation
  with the id `organisation_id` name (`Rescord.Storage.Named`, ADR 0091).
  It reads the table with no actor, for `bin/check-files`.
  """
  @spec file_keys(String.t()) :: [Storage.Named.entry()]
  def file_keys(organisation_id) do
    for %{id: id} <- Accounts.erased_members("org_" <> organisation_id),
        do: {marker_key(organisation_id, id), "marker of an erasure", id}
  end

  @doc """
  Erases again each person whom a marker in the store names and whom the
  database does not show as erased: after the restore of a dump from
  before the erasure (ADR 0105). Each such member gets the number of the
  marker, and an account with no membership left loses its email. Writes
  each marker that an erased member names and the store does not have.
  Returns the count of the people that it erased again.
  """
  @spec reapply_erasures() :: {:ok, non_neg_integer} | {:error, term}
  def reapply_erasures do
    with {:ok, files} <- Storage.files() do
      count =
        for {key, _size} <- files,
            [organisation_id, "erasures", _member_id] <- [String.split(key, "/")],
            {:ok, bytes} <- [Storage.get(key)],
            {:ok, body} <- [Jason.decode(bytes)],
            reapply(organisation_id, body) == :erased,
            reduce: 0 do
          count -> count + 1
        end

      rewrite_markers()
      {:ok, count}
    end
  end

  defp reapply(organisation_id, %{"member_id" => member_id, "user_id" => user_id} = body) do
    tenant = "org_" <> organisation_id

    with true <- tenant in Repo.all_tenants(),
         {:ok, %{erased_at: nil} = member} <-
           Accounts.member_with_former(member_id, tenant: tenant, authorize?: false),
         user = user!(user_id),
         options = Correlation.start(tenant: tenant, authorize?: false),
         {:ok, member} <- remove_if_member(member, internal(options)),
         {:ok, _erased} <-
           Accounts.erase_member(
             member,
             %{keep_comments: false, former_number: body["former_number"]},
             internal(options)
           ) do
      unless user.root? or Accounts.memberships(user.id) != [] or is_nil(user.email),
        do: forget_account(user, options)

      :erased
    else
      _erased_or_gone -> :as_it_was
    end
  end

  defp reapply(_organisation_id, _body), do: :as_it_was

  defp rewrite_markers do
    for "org_" <> organisation_id = tenant <- Repo.all_tenants(),
        member <- Accounts.erased_members(tenant),
        key = marker_key(organisation_id, member.id),
        Storage.get(key) == {:error, :not_found} do
      write_marker(%{
        key: key,
        body: %{
          "organisation_id" => organisation_id,
          "member_id" => member.id,
          "user_id" => member.user_id,
          "former_number" => member.former_number
        }
      })
    end
  end
end
