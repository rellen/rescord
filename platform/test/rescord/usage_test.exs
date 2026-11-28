defmodule Rescord.UsageTest do
  @moduledoc """
  The usage counts (ADR 0098): what is counted and what is not, the
  memory and the database, the settings of a root user, and the send of
  each full day as OTLP or as the plain document.

  Not async: the counts of the memory and the mode are of the node. Other
  tests that run at the same time add their counts too, so a test counts
  items that only it uses, or reads the handler with events of its own.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures

  require Ash.Query

  alias Rescord.Repo
  alias Rescord.Usage
  alias Rescord.Usage.{Actions, Count, Counter, Document, Features, Settings}

  @mode {Rescord.Usage, :mode}

  setup do
    :persistent_term.erase(@mode)
    on_exit(fn -> :persistent_term.erase(@mode) end)
    %{root: root!()}
  end

  defp unique_item, do: "test.item.#{System.unique_integer([:positive])}"

  defp taken(item) do
    for {{_day, _feature, _kind, ^item}, number} <- Counter.take_all(), do: number
  end

  describe "the features" do
    test "each domain has a feature, or is left out with a reason" do
      for domain <- Application.fetch_env!(:rescord, :ash_domains) do
        short = Ash.Domain.Info.short_name(domain)

        assert short in Features.counted_domains() or
                 Map.has_key?(Features.left_out_domains(), short),
               "The domain #{short} has no feature in Rescord.Usage.Features"
      end
    end

    test "each feature of a domain or a resource is a key of the list" do
      for feature <- Map.values(Features.named_resources()), feature != nil do
        assert Features.feature?(feature)
      end

      for domain <- Features.counted_domains() do
        assert Features.feature?(Features.of_action(domain, :anything))
      end
    end

    test "each resource that the list names is a resource of its domain" do
      shorts =
        for domain <- Application.fetch_env!(:rescord, :ash_domains),
            resource <- Ash.Domain.Info.resources(domain),
            into: MapSet.new(),
            do: {Ash.Domain.Info.short_name(domain), Ash.Resource.Info.short_name(resource)}

      for {key, _feature} <- Features.named_resources() do
        assert key in shorts, "#{inspect(key)} is no resource"
      end
    end
  end

  describe "counting" do
    test "a count goes to the memory, and a flush adds it to the row of the day" do
      item = unique_item()
      Usage.count(:expenses, :action, item)
      Usage.count(:expenses, :action, item)
      :ok = Usage.flush()

      assert [%Count{count: 2, feature: :expenses, kind: :action}] =
               Count |> Ash.Query.filter(item == ^item) |> Ash.read!(authorize?: false)

      Usage.count(:expenses, :action, item)
      :ok = Usage.flush()

      assert [%Count{count: 3, day: day}] =
               Count |> Ash.Query.filter(item == ^item) |> Ash.read!(authorize?: false)

      assert day == Date.utc_today()
    end

    test "each count is an event of telemetry, for the metrics endpoint" do
      ref = make_ref()
      test = self()

      :telemetry.attach(
        "usage-test-#{inspect(ref)}",
        [:rescord, :usage, :count],
        fn _event, measurements, metadata, _config ->
          if metadata.feature == :tools, do: send(test, {ref, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("usage-test-#{inspect(ref)}") end)

      Usage.count(:tools, :page, unique_item())
      assert_receive {^ref, %{count: 1}, %{feature: :tools, kind: :page} = metadata}
      # The item is not a tag: the counter has a series for each feature and kind.
      refute Map.has_key?(metadata, :item)
    end

    test "the mode off counts nothing, and a flush empties the memory", %{root: root} do
      assert {:ok, %Settings{mode: :off}} = Usage.save_settings(%{mode: :off}, actor: root)
      item = unique_item()
      Usage.count(:expenses, :action, item)
      assert taken(item) == []

      Counter.add({:expenses, :action, item})
      :ok = Usage.flush()
      assert Count |> Ash.Query.filter(item == ^item) |> Ash.read!(authorize?: false) == []
    end

    test "a count that cannot be written goes back into the memory" do
      item = String.duplicate("x", 300)
      Counter.add({:expenses, :action, item})
      :ok = Usage.flush()
      assert taken(item) == [1]
    end

    test "only the outer action of a person counts, by domain, resource and action" do
      user = %Rescord.Accounts.User{id: Ash.UUID.generate()}
      outer = %{actor: user, resource_short_name: :expense, action: :approve}
      inner = %{actor: user, resource_short_name: :receipt, action: :attach}

      Actions.handle([:ash, :expenses, :update, :start], %{}, outer, nil)
      Actions.handle([:ash, :expenses, :create, :start], %{}, inner, nil)
      Actions.handle([:ash, :expenses, :create, :stop], %{}, inner, nil)
      assert taken("expenses.receipt.attach") == []
      Actions.handle([:ash, :expenses, :update, :stop], %{}, outer, nil)

      assert taken("expenses.expense.approve") == [1]
      assert taken("expenses.receipt.attach") == []
    end

    test "an action with no person as its actor does not count" do
      metadata = %{actor: nil, resource_short_name: :task, action: :generate_task_ritual}
      Actions.handle([:ash, :tasks, :create, :start], %{}, metadata, nil)
      Actions.handle([:ash, :tasks, :create, :stop], %{}, metadata, nil)
      assert taken("tasks.task.generate_task_ritual") == []
    end

    test "the sign-in is not counted" do
      user = %Rescord.Accounts.User{id: Ash.UUID.generate()}
      metadata = %{actor: user, resource_short_name: :token, action: :store_token_ritual}
      Actions.handle([:ash, :accounts, :create, :start], %{}, metadata, nil)
      Actions.handle([:ash, :accounts, :create, :stop], %{}, metadata, nil)
      assert taken("accounts.token.store_token_ritual") == []
    end

    test "a real action of a root user counts with the names of the code", %{root: root} do
      Counter.take_all()
      organisation!(root)

      assert Enum.any?(Counter.take_all(), fn {{_day, feature, kind, item}, _number} ->
               feature == :settings and kind == :action and
                 String.starts_with?(item, "accounts.organisation.")
             end)
    end
  end

  describe "the settings" do
    test "a server with no row is in the mode local, and the first save makes the row", %{
      root: root
    } do
      assert %Settings{mode: :local, format: :otlp, installation_id: nil} =
               Usage.settings(actor: root)

      assert {:ok, %Settings{mode: :local, installation_id: id}} =
               Usage.save_settings(%{format: :json}, actor: root)

      assert is_binary(id)
      assert Usage.mode() == :local
    end

    test "only a root user reads or changes them", %{root: root} do
      {:ok, _settings} = Usage.save_settings(%{mode: :local}, actor: root)
      stranger = Ash.Seed.seed!(Rescord.Accounts.User, %{email: unique_address()})

      assert {:ok, nil} = Ash.read_one(Settings, actor: stranger)
      assert {:error, _forbidden} = Usage.save_settings(%{mode: :off}, actor: stranger)
      assert [] = Usage.counts_since(Date.utc_today(), actor: stranger)
    end

    test "the mode send needs an address, which is https or this machine", %{root: root} do
      assert {:error, error} = Usage.save_settings(%{mode: :send}, actor: root)
      assert error_on(error, :endpoint) =~ "give the address"

      assert {:error, error} =
               Usage.save_settings(%{mode: :send, endpoint: "ftp://example.org"}, actor: root)

      assert error_on(error, :endpoint) =~ "https://"

      assert {:error, error} =
               Usage.save_settings(
                 %{mode: :send, endpoint: "https://user:secret@example.org/v1/metrics"},
                 actor: root
               )

      assert error_on(error, :endpoint) =~ "no user or password"

      assert {:ok, %Settings{mode: :send, sending_since: since}} =
               Usage.save_settings(
                 %{mode: :send, endpoint: "https://collector.example.org/v1/metrics"},
                 actor: root
               )

      assert since == Date.utc_today()
      assert Usage.mode() == :send
    end

    test "a token goes only to https or to this machine, and no version holds it", %{
      root: root
    } do
      {:ok, _settings} =
        Usage.save_settings(%{endpoint: "http://collector.example.org/v1/metrics"}, actor: root)

      assert {:error, error} = Usage.save_token("a-token-of-the-collector", actor: root)
      assert error_on(error, :endpoint) =~ "a token goes only"

      {:ok, _settings} =
        Usage.save_settings(%{endpoint: "http://localhost:4318/v1/metrics"}, actor: root)

      assert {:ok, %Settings{token_hint: "ctor", token_set_at: %DateTime{}} = settings} =
               Usage.save_token("a-token-of-the-collector", actor: root)

      # A token cannot be emptied by an empty text.
      assert {:error, _error} = Usage.save_token("", actor: root)

      %{rows: rows} = Repo.query!("select changes::text from usage_settings_versions")
      refute Enum.any?(rows, fn [changes] -> changes =~ "a-token-of-the-collector" end)
      refute Enum.any?(rows, fn [changes] -> changes =~ "encrypted_token" end)

      # The token cannot be read with the settings.
      assert_raise Ash.Error.Forbidden, fn -> Ash.load!(settings, :token, actor: root) end
    end

    test "a problem names the values of its rule" do
      error = %{
        errors: [%{field: :endpoint, message: "is at most %{max} long", vars: [max: 2000]}]
      }

      assert Usage.problems(error) == [{:endpoint, "is at most 2000 long"}]
    end

    test "a new installation id cuts the tie to what was sent before", %{root: root} do
      {:ok, %Settings{installation_id: before}} = Usage.save_settings(%{}, actor: root)
      {:ok, %Settings{installation_id: now}} = Usage.renew_installation(actor: root)
      assert before != now
    end

    test "a root user deletes each stored count", %{root: root} do
      item = unique_item()
      Usage.count(:tools, :page, item)
      :ok = Usage.flush()
      assert :ok = Usage.forget_counts(actor: root)
      assert Ash.read!(Count, authorize?: false) == []
    end
  end

  describe "the documents" do
    setup do
      counts = [
        %Count{feature: :residents, kind: :page, item: "residents", count: 31},
        %Count{feature: :expenses, kind: :action, item: "expenses.expense.approve", count: 4}
      ]

      %{counts: counts, id: Ash.UUID.generate()}
    end

    test "OTLP has one delta sum, a point for each count, and nothing of the host", %{
      counts: counts,
      id: id
    } do
      document = Document.day(:otlp, id, ~D[2026-11-27], counts) |> Jason.decode!()

      assert %{"resourceMetrics" => [%{"resource" => resource, "scopeMetrics" => [scope]}]} =
               document

      assert resource["attributes"] == [
               %{"key" => "service.name", "value" => %{"stringValue" => "rescord"}},
               %{"key" => "service.version", "value" => %{"stringValue" => Rescord.version()}},
               %{"key" => "service.instance.id", "value" => %{"stringValue" => id}}
             ]

      assert %{"scope" => %{"name" => "rescord.usage"}, "metrics" => [metric]} = scope
      assert metric["name"] == "rescord.usage.count"
      assert %{"aggregationTemporality" => 1, "isMonotonic" => true} = metric["sum"]
      assert [expenses, residents] = metric["sum"]["dataPoints"]

      assert expenses == %{
               "attributes" => [
                 %{"key" => "feature", "value" => %{"stringValue" => "expenses"}},
                 %{"key" => "kind", "value" => %{"stringValue" => "action"}},
                 %{"key" => "item", "value" => %{"stringValue" => "expenses.expense.approve"}}
               ],
               "startTimeUnixNano" => "1795737600000000000",
               "timeUnixNano" => "1795824000000000000",
               "asInt" => "4"
             }

      assert residents["asInt"] == "31"
    end

    test "the plain document has the day, the installation and the counts", %{
      counts: counts,
      id: id
    } do
      assert Document.day(:json, id, ~D[2026-11-27], counts) |> Jason.decode!() == %{
               "schema" => "rescord.usage/1",
               "installation" => id,
               "rescord" => Rescord.version(),
               "day" => "2026-11-27",
               "counts" => [
                 %{
                   "feature" => "expenses",
                   "kind" => "action",
                   "item" => "expenses.expense.approve",
                   "count" => 4
                 },
                 %{
                   "feature" => "residents",
                   "kind" => "page",
                   "item" => "residents",
                   "count" => 31
                 }
               ]
             }
    end

    test "a test has no count", %{id: id} do
      assert %{"test" => true, "counts" => []} = Document.test(:json, id) |> Jason.decode!()

      assert %{"resourceMetrics" => [%{"scopeMetrics" => []}]} =
               Document.test(:otlp, id) |> Jason.decode!()
    end
  end

  describe "the send of each hour" do
    setup %{root: root} do
      {:ok, _settings} =
        Usage.save_settings(
          %{mode: :send, endpoint: "https://collector.example.org/v1/metrics"},
          actor: root
        )

      {:ok, _settings} = Usage.save_token("a-token-of-the-collector", actor: root)
      today = Date.utc_today()
      # Sending was turned on ten days ago.
      Repo.query!("update usage_settings set sending_since = $1", [Date.add(today, -10)])

      for {days, number} <- [{-12, 5}, {-9, 6}, {-3, 7}, {-1, 8}, {0, 9}] do
        Usage.add_count!(Date.add(today, days), :tools, :page, "dose", number, authorize?: false)
      end

      %{today: today}
    end

    test "sends each full day of the last 7 with a count, oldest first", %{today: today} do
      test = self()

      Req.Test.stub(Rescord.Usage.Sender, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:sent, conn.method, conn.request_path, conn.req_headers, Jason.decode!(body)})
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      assert :ok = Usage.send_due(today)

      assert_received {:sent, "POST", "/v1/metrics", headers, first}
      assert {"authorization", "Bearer a-token-of-the-collector"} in headers
      assert {"content-type", "application/json"} in headers
      assert as_int(first) == "7"

      assert_received {:sent, "POST", "/v1/metrics", _headers, second}
      assert as_int(second) == "8"

      # Not the day of 9 days ago: it is older than 7 days. Not today: it is
      # not full.
      refute_received {:sent, _method, _path, _headers, _body}

      settings = Ash.read_one!(Settings, authorize?: false)
      assert settings.last_sent_day == Date.add(today, -1)
      assert settings.last_result == :ok
      assert settings.last_status == 200

      # The next hour sends nothing again.
      assert :ok = Usage.send_due(today)
      refute_received {:sent, _method, _path, _headers, _body}
    end

    test "a day that the address does not take stays for the next hour", %{today: today} do
      Req.Test.stub(Rescord.Usage.Sender, &Plug.Conn.send_resp(&1, 503, ""))
      assert :ok = Usage.send_due(today)

      settings = Ash.read_one!(Settings, authorize?: false)
      assert settings.last_result == :status
      assert settings.last_status == 503
      assert settings.last_sent_day == Date.add(today, -4)

      Req.Test.stub(Rescord.Usage.Sender, &Plug.Conn.send_resp(&1, 202, ""))
      assert :ok = Usage.send_due(today)
      assert Ash.read_one!(Settings, authorize?: false).last_sent_day == Date.add(today, -1)
    end

    test "no answer is a day for the next hour too", %{today: today} do
      Req.Test.stub(Rescord.Usage.Sender, &Req.Test.transport_error(&1, :econnrefused))
      assert :ok = Usage.send_due(today)
      assert Ash.read_one!(Settings, authorize?: false).last_result == :unreachable
    end

    test "the mode local sends nothing", %{root: root, today: today} do
      {:ok, _settings} = Usage.save_settings(%{mode: :local}, actor: root)
      Req.Test.stub(Rescord.Usage.Sender, fn _conn -> flunk("sent in the mode local") end)
      assert :ok = Usage.send_due(today)
    end

    test "Send a test sends a document with no count, and notes the answer", %{root: root} do
      test = self()

      Req.Test.stub(Rescord.Usage.Sender, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:sent, Jason.decode!(body)})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, %Settings{test_result: :ok, test_status: 200}} = Usage.send_test(actor: root)
      assert_received {:sent, %{"resourceMetrics" => [%{"scopeMetrics" => []}]}}
    end

    test "the last full day is the newest day with a count before today", %{
      root: root,
      today: today
    } do
      assert Usage.last_full_day(today, actor: root) == Date.add(today, -1)
      assert Usage.last_full_day(Date.add(today, -12), actor: root) == nil
    end

    test "the counts older than 400 days go", %{today: today} do
      Usage.add_count!(Date.add(today, -401), :tools, :page, "dose", 1, authorize?: false)
      Req.Test.stub(Rescord.Usage.Sender, &Plug.Conn.send_resp(&1, 200, ""))
      :ok = Usage.send_due(today)

      days = Count |> Ash.read!(authorize?: false) |> Enum.map(& &1.day)
      refute Date.add(today, -401) in days
      assert Date.add(today, -12) in days
    end
  end

  defp as_int(%{"resourceMetrics" => [%{"scopeMetrics" => [%{"metrics" => [metric]}]}]}) do
    [point] = metric["sum"]["dataPoints"]
    point["asInt"]
  end

  defp error_on(%{errors: errors}, field) do
    Enum.find_value(errors, fn
      %{field: ^field, message: message} -> message
      _other -> nil
    end) || flunk("no error on #{field}: #{inspect(errors)}")
  end
end
