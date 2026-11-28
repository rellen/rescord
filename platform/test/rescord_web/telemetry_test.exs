defmodule RescordWeb.TelemetryTest do
  @moduledoc """
  Holds the metrics of Rescord and the endpoint that a collector reads
  (ADR 0077): what the endpoint answers, which metrics it has, and that no
  tag holds a value that a client sends.
  """

  use RescordWeb.ConnCase, async: false

  import Rescord.AccountsFixtures

  alias RescordWeb.Telemetry

  # A port that the system gives, so that two runs do not meet.
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp start_reporter(_context) do
    port = free_port()
    Rescord.Metrics.attach()

    for child <- Telemetry.reporter(port: port, ip: {127, 0, 0, 1}) do
      start_supervised!(child)
    end

    {:ok, metrics_url: "http://127.0.0.1:#{port}"}
  end

  defp scrape(context) do
    response = Req.get!(context.metrics_url <> "/metrics", retry: false)
    assert response.status == 200
    response.body
  end

  test "with no port, nothing reports" do
    assert Telemetry.reporter([]) == []
    assert Telemetry.reporter(port: nil) == []
  end

  test "each metric has a name of Rescord, a description and a kind that the reporter has" do
    metrics = Telemetry.metrics()
    names = Enum.map(metrics, &Enum.join(&1.name, "."))

    assert names == Enum.uniq(names)

    for metric <- metrics do
      assert hd(metric.name) == :rescord
      assert is_binary(metric.description)

      # Peep has no summary.
      assert metric.__struct__ in [
               Elixir.Telemetry.Metrics.Counter,
               Elixir.Telemetry.Metrics.Distribution,
               Elixir.Telemetry.Metrics.LastValue,
               Elixir.Telemetry.Metrics.Sum
             ]
    end
  end

  describe "the endpoint" do
    setup :start_reporter

    test "answers the metrics on /metrics, and 404 for each other path", context do
      assert scrape(context) =~ "# EOF"

      for path <- ["/", "/health", "/sign-in", "/metrics/more"] do
        assert Req.get!(context.metrics_url <> path, retry: false).status == 404
      end
    end

    test "counts a request by its route and its status, and an action of Ash", context do
      root = root!()
      organisation = organisation!(root, "Wattle Creek")
      {_member, user} = member!(organisation, :member, root)

      assert context.conn
             |> sign_in(user)
             |> get(~p"/o/#{organisation.short_name}")
             |> html_response(200)

      body = scrape(context)

      assert body =~ ~s(rescord_http_request_duration_milliseconds_count{status="200"})
      assert body =~ ~s(rescord_http_route_duration_milliseconds_count{route="/o/:organisation"})

      assert body =~
               ~s(rescord_page_mount_duration_milliseconds_count{view="RescordWeb.OrganisationLive"})

      assert body =~ ~r/rescord_action_duration_milliseconds_count\{[^}]*domain="accounts"/
      assert body =~ "rescord_repo_query_duration_milliseconds_bucket"

      # A tag holds no name of an organisation, and no id of a person.
      refute body =~ organisation.short_name
      refute body =~ organisation.id
      refute body =~ user.id
    end

    test "counts a job that fails by its worker, and never by its arguments", context do
      # The handler of the log writes a line for the same event.
      ExUnit.CaptureLog.capture_log(fn ->
        :telemetry.execute(
          [:oban, :job, :exception],
          %{duration: 1_000, queue_time: 1_000},
          %{
            job: %Oban.Job{
              worker: "Rescord.SomeWorker",
              queue: "default",
              args: %{"email" => "fern@example.org"}
            },
            state: :failure
          }
        )
      end)

      body = scrape(context)

      assert body =~ ~r/rescord_job_exception_count\{[^}]*worker="Rescord.SomeWorker"/
      assert body =~ ~r/rescord_job_exception_count\{[^}]*state="failure"/
      refute body =~ "fern"
    end

    test "counts an email by its result", context do
      :telemetry.execute([:swoosh, :deliver, :stop], %{duration: 1}, %{mailer: Rescord.Mailer})

      :telemetry.execute([:swoosh, :deliver, :stop], %{duration: 1}, %{
        mailer: Rescord.Mailer,
        error: {:retries_exceeded, "fern@example.org"}
      })

      body = scrape(context)

      assert body =~ ~s(rescord_mail_count{result="ok"} 1)
      assert body =~ ~s(rescord_mail_count{result="error"} 1)
      refute body =~ "fern"
    end

    test "counts a reply of the assistant by how it ended, and sums its tokens", context do
      measures = %{
        requests: 2,
        input_tokens: 300,
        cache_read_tokens: 40,
        cache_write_tokens: 50,
        output_tokens: 70,
        cost_microdollars: 1_900
      }

      :telemetry.execute([:rescord, :ruby, :reply, :stop], measures, %{
        state: :complete,
        reason: nil
      })

      :telemetry.execute([:rescord, :ruby, :reply, :stop], measures, %{
        state: :failed,
        reason: :provider_limit
      })

      body = scrape(context)

      assert body =~ ~r/rescord_ruby_reply_count\{[^}]*state="complete"[^}]*\} 1/
      assert body =~ ~r/rescord_ruby_reply_count\{[^}]*reason="provider_limit"[^}]*\} 1/
      assert body =~ ~r/rescord_ruby_reply_requests_total(\{\})? 4/
      assert body =~ ~r/rescord_ruby_reply_input_tokens(\{\})? 600/
      assert body =~ ~r/rescord_ruby_reply_cache_read_tokens(\{\})? 80/
      assert body =~ ~r/rescord_ruby_reply_cache_write_tokens(\{\})? 100/
      assert body =~ ~r/rescord_ruby_reply_output_tokens(\{\})? 140/
      assert body =~ ~r/rescord_ruby_reply_cost_microdollars(\{\})? 3800/
    end
  end
end
