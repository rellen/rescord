defmodule Rescord.Health do
  @moduledoc """
  The sanity checks of the server (ADR 0114, issue 38): checks that run on
  their own, find drift in the data and in the server, and say so.

  A check (`Rescord.Health.Check`) reads the database, or asks the server,
  and gives a level, a count and at most 20 ids. `Rescord.Health.Checks`
  lists them. The job `Rescord.Health.Workers.Run` starts `run_due/1` each
  hour, which runs each check that is due:

  - each run of a check is one transaction that PostgreSQL holds read-only,
    with a limit of time for each statement, and that `run/2` rolls back.
    A fault in a check cannot change data;
  - a check reads the tables with SQL and the schema of the organisation,
    not through Ash actions: it looks for rows that the policies, the
    default filters and the validations are there to stop;
  - the checks run one after the other, in the queue `health`.

  What a run found is a `Rescord.Health.Result`, one row for each check
  and scope. `/root/health` shows them, `bin/check` reads them, and the
  metric `rescord.health.level` gives the worst level of each check. A
  change of level writes one log line, with the check, the level and the
  count: never a value of a row.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary]

  require Ash.Query
  require Logger

  alias Rescord.Health.{Checks, Result}
  alias Rescord.Repo

  boundary do
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Vault, Rescord.Transfers]
    exports [Checks, Rescord.Health.Workers.Run]
  end

  resources do
    resource Result
  end

  @periods %{hourly: 3_600, daily: 86_400, weekly: 604_800}
  # A run each hour starts a minute or two late or early: a check is due a
  # little before its period has passed.
  @slack 600
  @unknown_runs_to_fail 3

  @doc """
  Runs each check that is due at `now`: a check that has no result yet, or
  whose last run is older than its period. Gives the results that it
  wrote.
  """
  @spec run_due(DateTime.t()) :: [Result.t()]
  def run_due(now \\ DateTime.utc_now()) do
    forget_old_checks()
    last = last_runs()

    for check <- Checks.all(), due?(check, last, now), result <- run_check(check, now) do
      result
    end
  end

  @typedoc "What a page says of a check."
  @type description :: %{
          name: atom,
          title: String.t(),
          explain: String.t(),
          scope: :server | :organisation,
          cadence: :hourly | :daily | :weekly
        }

  @doc "What each check looks for, in the order of `Rescord.Health.Checks.all/0`."
  @spec checks() :: [description]
  def checks, do: Enum.map(Checks.all(), &description/1)

  @doc "What the check with `name` looks for."
  @spec describe(atom) :: description
  def describe(name), do: name |> Checks.find() |> description()

  defp description(check) do
    %{
      name: check.name(),
      title: check.title(),
      explain: check.explain(),
      scope: check.scope(),
      cadence: check.cadence()
    }
  end

  @doc """
  Runs each check now, due or not, at the wish of a root user: the button
  of `/root/health`. Refuses each other actor.
  """
  @spec run_now(keyword) :: :ok | {:error, :forbidden}
  def run_now(opts) do
    case Keyword.get(opts, :actor) do
      %{root?: true} ->
        now = DateTime.utc_now()
        Enum.each(Checks.all(), &run_check(&1, now))

      _other ->
        {:error, :forbidden}
    end
  end

  @doc "Runs one check now, for each of its scopes, and writes its results."
  @spec run_check(module, DateTime.t()) :: [Result.t()]
  def run_check(check, now \\ DateTime.utc_now()) do
    results =
      for {organisation, prefix} <- scopes(check) do
        context = %{now: now, organisation: organisation, prefix: prefix}
        record(check, organisation, run(check, context), now)
      end

    emit(check, results)
    results
  end

  @doc """
  Runs `check` with `context` inside a read-only transaction, and rolls it
  back. Gives `{:ok, finding, milliseconds}`, or `{:unknown, milliseconds}`
  when the check raised or ran out of time.
  """
  @spec run(module, Rescord.Health.Check.context()) ::
          {:ok, Rescord.Health.Check.finding(), non_neg_integer} | {:unknown, non_neg_integer}
  def run(check, context) do
    started = System.monotonic_time(:millisecond)
    timeout = if function_exported?(check, :timeout, 0), do: check.timeout(), else: 10_000

    outcome =
      try do
        read_only(timeout, fn -> check.run(context) end)
      rescue
        error ->
          Logger.warning(
            "The check #{check.name()} could not run#{scope_words(context)}: " <>
              Rescord.Log.reason(error)
          )

          :unknown
      end

    elapsed = System.monotonic_time(:millisecond) - started

    case outcome do
      %{level: level, count: count, ids: ids} = finding
      when level in [:ok, :note, :fail] and is_integer(count) and is_list(ids) ->
        {:ok, %{finding | ids: Enum.take(ids, 20)}, elapsed}

      _unknown ->
        {:unknown, elapsed}
    end
  end

  # The transaction gives back what the check found by its rollback, so a
  # check never commits, and in the tests the savepoint takes the settings
  # of the transaction away again.
  defp read_only(timeout, fun) do
    result =
      Repo.transaction(
        fn ->
          Repo.query!("SET TRANSACTION READ ONLY")
          Repo.query!("SELECT set_config('statement_timeout', $1, true)", ["#{timeout}"])
          Repo.query!("SET LOCAL lock_timeout = '1s'")
          Repo.rollback({:found, fun.()})
        end,
        timeout: timeout * 10
      )

    case result do
      {:error, {:found, finding}} -> finding
    end
  end

  defp scope_words(%{organisation: nil}), do: ""
  defp scope_words(%{organisation: organisation}), do: " for the organisation #{organisation.id}"

  defp scopes(check) do
    case check.scope() do
      :server ->
        [{nil, nil}]

      :organisation ->
        for organisation <- Rescord.Accounts.all_organisations(),
            do: {organisation, "org_" <> organisation.id}
    end
  end

  defp record(check, organisation, outcome, now) do
    organisation_id = organisation && organisation.id
    before = last_result(check.name(), organisation_id)

    {finding, unknown_runs, elapsed} =
      case outcome do
        {:ok, finding, elapsed} ->
          {finding, 0, elapsed}

        {:unknown, elapsed} ->
          runs = ((before && before.unknown_runs) || 0) + 1
          level = if runs >= @unknown_runs_to_fail, do: :fail, else: :unknown
          {%{level: level, count: 0, ids: []}, runs, elapsed}
      end

    since = if before && before.level == finding.level, do: before.since, else: now

    if before == nil or before.level != finding.level do
      Logger.log(
        log_level(finding.level),
        "The check #{check.name()}#{scope_words(%{organisation: organisation})} " <>
          "is #{finding.level} with a count of #{finding.count}"
      )
    end

    Result
    |> Ash.Changeset.for_create(
      :record,
      %{
        check: check.name(),
        organisation_id: organisation_id,
        level: finding.level,
        count: finding.count,
        ids: finding.ids,
        since: since,
        unknown_runs: unknown_runs,
        checked_at: now,
        duration_ms: Kernel.max(elapsed, 0),
        alerted_at: before && before.alerted_at
      },
      authorize?: false
    )
    |> Ash.create!()
  end

  defp log_level(:fail), do: :error
  defp log_level(:unknown), do: :warning
  defp log_level(_level), do: :info

  defp last_result(name, organisation_id) do
    Result
    |> Ash.Query.filter(check == ^name)
    |> filter_organisation(organisation_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp filter_organisation(query, nil), do: Ash.Query.filter(query, is_nil(organisation_id))
  defp filter_organisation(query, id), do: Ash.Query.filter(query, organisation_id == ^id)

  # The oldest run of each check, so that a check is due once any of its
  # scopes waits.
  defp last_runs do
    %{rows: rows} =
      Repo.query!(
        "select \"check\", min(checked_at) from health_results group by \"check\"",
        []
      )

    Map.new(rows, fn [name, checked_at] -> {name, checked_at} end)
  end

  defp due?(check, last, now) do
    case Map.fetch(last, Atom.to_string(check.name())) do
      :error ->
        true

      {:ok, %NaiveDateTime{} = checked_at} ->
        due?(
          check,
          %{last | Atom.to_string(check.name()) => DateTime.from_naive!(checked_at, "Etc/UTC")},
          now
        )

      {:ok, %DateTime{} = checked_at} ->
        DateTime.diff(now, checked_at) >= Map.fetch!(@periods, check.cadence()) - @slack
    end
  end

  # A check that a newer version took out leaves its rows: they go.
  defp forget_old_checks do
    names = Enum.map(Checks.names(), &Atom.to_string/1)
    Repo.query!("delete from health_results where not (\"check\" = any($1))", [names])
  end

  # The metric of ADR 0077: the worst level of the check, in each scope.
  defp emit(check, results) do
    worst = results |> Enum.map(& &1.level) |> worst()

    :telemetry.execute(
      [:rescord, :health, :check],
      %{level: level_number(worst)},
      %{check: check.name()}
    )
  end

  @doc "The worst of some levels: `:fail`, then `:unknown`, then `:note`, then `:ok`."
  @spec worst([atom]) :: atom
  def worst(levels) do
    Enum.find([:fail, :unknown, :note], :ok, &(&1 in levels))
  end

  @doc "The number of a level, for the metric: 0 ok, 1 note, 2 fail, 3 unknown."
  @spec level_number(atom) :: 0..3
  def level_number(:ok), do: 0
  def level_number(:note), do: 1
  def level_number(:fail), do: 2
  def level_number(:unknown), do: 3

  @doc """
  The results, the server first and then each organisation, each in the
  order of `Rescord.Health.Checks.all/0`, with the organisation loaded.
  """
  @spec results(keyword) :: [Result.t()]
  def results(opts) do
    order = Checks.names() |> Enum.with_index() |> Map.new()

    Result
    |> Ash.Query.load(:organisation)
    |> Ash.read!(opts)
    |> Enum.sort_by(fn result ->
      {if(result.organisation, do: 1, else: 0),
       result.organisation && result.organisation.short_name, Map.get(order, result.check, 999)}
    end)
  end

  @typedoc "How many results have each level, and when the newest run was."
  @type summary :: %{
          ok: non_neg_integer,
          note: non_neg_integer,
          fail: non_neg_integer,
          unknown: non_neg_integer,
          failing: [atom],
          checked_at: DateTime.t() | nil
        }

  @doc "A count of the results by level, and the time of the newest run."
  @spec summary(keyword) :: summary
  def summary(opts) do
    results = Ash.read!(Result, opts)
    counts = Enum.frequencies_by(results, & &1.level)

    %{
      ok: Map.get(counts, :ok, 0),
      note: Map.get(counts, :note, 0),
      fail: Map.get(counts, :fail, 0),
      unknown: Map.get(counts, :unknown, 0),
      failing: for(%{level: :fail, check: check} <- results, uniq: true, do: check),
      checked_at: results |> Enum.map(& &1.checked_at) |> Enum.max(DateTime, fn -> nil end)
    }
  end
end
