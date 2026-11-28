defmodule Rescord.HealthTest do
  @moduledoc """
  The sanity checks (ADR 0114, issue 38): the runner, the results, the
  read-only transaction, and the checks of the server.
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures

  alias Rescord.{Health, Repo}
  alias Rescord.Health.{Checks, Result}

  defp context(organisation \\ nil) do
    %{
      now: DateTime.utc_now(),
      organisation: organisation,
      prefix: organisation && "org_" <> organisation.id
    }
  end

  defp found(check, context), do: Health.run(check, context)

  defp results do
    Ash.read!(Result, authorize?: false)
  end

  describe "the list of the checks" do
    test "names/0 is the name of each check of all/0, in its order" do
      assert Checks.names() == Enum.map(Checks.all(), & &1.name())
    end

    test "each check says what it looks for, and what a fault means" do
      for check <- Checks.all() do
        assert check.scope() in [:server, :organisation]
        assert check.cadence() in [:hourly, :daily, :weekly]
        assert is_binary(check.title()) and check.title() != ""
        assert is_binary(check.explain()) and check.explain() != ""
      end
    end

    test "the runner is in the crontab, and checks itself as an hourly job" do
      assert "Rescord.Health.Workers.Run" in Checks.Cron.hourly_workers()
    end
  end

  describe "a run of a check" do
    defmodule Writes do
      @moduledoc false
      use Rescord.Health.Check
      def name, do: :clock
      def scope, do: :server
      def cadence, do: :hourly
      def title, do: "A check that writes"
      def explain, do: "It must not."

      def run(_context) do
        Rescord.Repo.query!("create table health_test_written (id int)", [])
        ok()
      end
    end

    defmodule Slow do
      @moduledoc false
      use Rescord.Health.Check
      def name, do: :clock
      def scope, do: :server
      def cadence, do: :hourly
      def title, do: "A slow check"
      def explain, do: "It runs out of time."
      def timeout, do: 100

      def run(_context) do
        Rescord.Repo.query!("select pg_sleep(1)", [])
        ok()
      end
    end

    test "a check that writes cannot: PostgreSQL refuses it, and the check is unknown" do
      log = capture_log(fn -> assert {:unknown, _ms} = found(Writes, context()) end)
      assert log =~ "could not run"

      assert %{rows: [[false]]} =
               Repo.query!("select to_regclass('public.health_test_written') is not null", [])

      # The test can write again: the rollback took the setting away.
      assert {:ok, _} = Repo.query("create temporary table health_test_after (id int)", [])
    end

    test "a check that runs out of time is unknown" do
      capture_log(fn -> assert {:unknown, _ms} = found(Slow, context()) end)
    end

    test "three unknown runs in a row are a fault" do
      capture_log(fn ->
        for _run <- 1..2, do: Health.run_check(Writes)
        assert [%{level: :unknown, unknown_runs: 2}] = results()

        Health.run_check(Writes)
        assert [%{level: :fail, unknown_runs: 3}] = results()
      end)
    end

    test "a result keeps the time its level changed, and a run writes the row again" do
      first = ~U[2026-11-28 10:00:00.000000Z]
      later = ~U[2026-11-28 11:00:00.000000Z]

      [%{since: ^first, checked_at: ^first}] = Health.run_check(Checks.Clock, first)
      [%{since: ^first, checked_at: ^later}] = Health.run_check(Checks.Clock, later)
      assert [_one] = results()
    end

    test "run_due/1 runs a check once in its period" do
      now = DateTime.utc_now()
      ran = Health.run_due(now) |> Enum.map(& &1.check) |> Enum.uniq()
      server_checks = for check <- Checks.all(), check.scope() == :server, do: check.name()
      assert Enum.sort(server_checks) == Enum.sort(ran -- [:managers])

      assert Health.run_due(DateTime.add(now, 60, :second)) == []

      # With no organisation, a check of each organisation has no scope.
      hourly =
        for check <- Checks.all(),
            check.cadence() == :hourly and check.scope() == :server,
            do: check.name()

      again = Health.run_due(DateTime.add(now, 3_600, :second)) |> Enum.map(& &1.check)
      assert Enum.sort(Enum.uniq(again)) == Enum.sort(hourly)
    end

    test "a check emits its worst level for the metric" do
      handler = "health-test-#{System.unique_integer()}"
      test = self()

      :telemetry.attach(
        handler,
        [:rescord, :health, :check],
        fn _event, measurements, metadata, _config ->
          send(test, {:level, metadata.check, measurements.level})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      Health.run_check(Checks.Clock)
      assert_received {:level, :clock, 0}
    end

    test "the summary counts the levels" do
      Health.run_check(Checks.Clock)
      assert %{ok: 1, fail: 0, checked_at: %DateTime{}} = Health.summary(authorize?: false)
    end

    test "only a root user reads the results" do
      Health.run_check(Checks.Clock)
      assert [_one] = Health.results(actor: root!())
      assert [] = Health.results(actor: user!())
    end
  end

  describe "the checks of the server" do
    test "the clock of the server and of the database agree here" do
      assert {:ok, %{level: :ok}, _ms} = found(Checks.Clock, context())
      assert %{level: :note, count: 5} = Checks.Clock.level(5)
      assert %{level: :fail, count: 31} = Checks.Clock.level(31)
    end

    test "each migration has run" do
      root = root!()
      organisation!(root)
      assert {:ok, %{level: :ok}, _ms} = found(Checks.Migrations, context())
    end

    test "an organisation whose schema is behind" do
      organisation = organisation!(root!())

      [[version]] =
        Repo.query!("select max(version) from \"org_#{organisation.id}\".schema_migrations", []).rows

      Repo.query!("delete from \"org_#{organisation.id}\".schema_migrations where version = $1", [
        version
      ])

      assert {:ok, %{level: :fail, count: 1, ids: [id]}, _ms} =
               found(Checks.Migrations, context())

      assert id == organisation.id
    end

    test "a server with no root user, and one with" do
      Repo.query!("update public.users set is_root = false", [])
      assert {:ok, %{level: :fail}, _ms} = found(Checks.RootUsers, context())
      root!()
      assert {:ok, %{level: :ok}, _ms} = found(Checks.RootUsers, context())
    end

    test "jobs that wait too long are a fault, and failed jobs a note" do
      now = DateTime.utc_now()
      assert {:ok, %{level: :ok}, _ms} = found(Checks.Jobs, context())

      insert_job("retryable", now)
      assert {:ok, %{level: :note, count: 1}, _ms} = found(Checks.Jobs, context())

      insert_job("available", DateTime.add(now, -20, :minute))
      assert {:ok, %{level: :fail, count: 2}, _ms} = found(Checks.Jobs, context())
    end

    test "an hourly job with no run in two hours is a fault, once the server is not new" do
      old = Map.put(context(), :uptime_ms, 4 * 3_600_000)
      young = Map.put(context(), :uptime_ms, 60_000)
      workers = Checks.Cron.hourly_workers()

      assert {:ok, %{level: :ok}, _ms} = found(Checks.Cron, young)
      assert {:ok, %{level: :fail, count: count}, _ms} = found(Checks.Cron, old)
      assert count == length(workers)

      for worker <- workers, do: insert_job("completed", DateTime.utc_now(), worker)
      assert {:ok, %{level: :ok}, _ms} = found(Checks.Cron, old)
    end

    test "a secret that a setting says is set, with no value" do
      assert {:ok, %{level: :ok}, _ms} = found(Checks.SecretsSet, context())

      %{rows: [[id]]} =
        Repo.query!(
          "insert into public.usage_settings (id, token_set_at, installation_id) " <>
            "values (gen_random_uuid(), now(), gen_random_uuid()) returning id",
          []
        )

      assert {:ok, %{level: :fail, count: 1, ids: [found_id]}, _ms} =
               found(Checks.SecretsSet, context())

      assert found_id == Ecto.UUID.load!(id)
    end

    test "the vault with no encrypted value" do
      assert {:ok, %{level: :ok}, _ms} = found(Checks.Vault, context())
    end
  end

  describe "the checks of an organisation" do
    test "an organisation with an administrator, and one where nobody can manage members" do
      root = root!()
      organisation = organisation!(root)
      {admin, _user} = member!(organisation, :administrator, root)
      assert {:ok, %{level: :ok}, _ms} = found(Checks.Managers, context(organisation))

      Repo.query!(
        "update \"org_#{organisation.id}\".members set role_id = " <>
          "(select id from \"org_#{organisation.id}\".roles where key = 'member') where id = $1",
        [Ecto.UUID.dump!(admin.id)]
      )

      assert {:ok, %{level: :fail, ids: [id]}, _ms} =
               found(Checks.Managers, context(organisation))

      assert id == organisation.id
    end

    test "an organisation with no member yet is not a fault" do
      organisation = organisation!(root!())
      assert {:ok, %{level: :ok}, _ms} = found(Checks.Managers, context(organisation))
    end
  end

  defp insert_job(state, at, worker \\ "Rescord.HealthTest.Nothing") do
    at = DateTime.to_naive(at)

    Repo.query!(
      """
      insert into public.oban_jobs
        (state, queue, worker, args, attempt, max_attempts, inserted_at, scheduled_at,
         attempted_at, completed_at)
      values (cast($1::text as oban_job_state), 'default', $2, '{}', 1, 20, $3::timestamp, $3::timestamp, $3::timestamp,
        case when $1::text = 'completed' then $3::timestamp end)
      """,
      [state, worker, at]
    )
  end
end
