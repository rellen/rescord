defmodule Rescord.HealthAlertsTest do
  @moduledoc """
  The alerts of the sanity checks (ADR 0114, issue 38, section 9): who
  gets one, when, and what leaves the server. Each channel sends to a stub
  of `Req.Test`, so no test reaches a push service or ntfy, and the jobs
  run with `Oban.drain_queue/1` in the process of the test.
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures

  alias Rescord.{Health, Notifications, Repo}
  alias Rescord.Health.{Alerts, Checks}
  alias Rescord.Notifications.WebPush

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    member!(organisation, :administrator, root)

    Req.Test.set_req_test_to_shared()
    on_exit(&Req.Test.set_req_test_to_private/0)
    test = self()

    Req.Test.stub(Rescord.Notifications.Channel, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:sent, conn.host, Map.new(conn.req_headers), body})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    {:ok, _} = Notifications.make_keys(actor: root)

    {:ok, _settings} =
      Notifications.save_settings(
        %{
          contact: "mailto:ops@example.org",
          push_on: true,
          ntfy_url: "https://ntfy.example.org",
          ntfy_on: true
        },
        actor: root
      )

    {:ok, root: root, organisation: organisation}
  end

  defp work!, do: Oban.drain_queue(queue: :default, with_recursion: true, with_safety: false)

  defp device!(user) do
    keys = WebPush.keys()

    {:ok, device} =
      Notifications.subscribe_device(
        %{
          endpoint: "https://fcm.googleapis.com/fcm/send/" <> Ecto.UUID.generate(),
          device_key: WebPush.encode(keys.public),
          auth: WebPush.encode(:crypto.strong_rand_bytes(16)),
          device: :android
        },
        actor: user
      )

    device
  end

  # A fault of the check of the managers: no role of the organisation has
  # the power to change the members, as only SQL can make it.
  defp fail!(context, now) do
    roles(context, "array_remove(powers, 'members')")
    Health.run_check(Checks.Managers, now)
  end

  defp pass!(context, now) do
    roles(context, "array_append(powers, 'members')")
    Health.run_check(Checks.Managers, now)
  end

  defp roles(context, powers) do
    Repo.query!(
      "update \"org_#{context.organisation.id}\".roles set powers = #{powers} where key = 'administrator'"
    )
  end

  defp sent do
    receive do
      {:sent, host, headers, body} -> [{host, headers, body} | sent()]
    after
      0 -> []
    end
  end

  test "a root user starts and stops their watch, and nobody else can", context do
    refute Health.watching?(actor: context.root)
    assert :ok = Health.watch(true, actor: context.root)
    assert :ok = Health.watch(true, actor: context.root)
    assert Health.watching?(actor: context.root)

    other = root!()
    refute Health.watching?(actor: other)

    user = user!()
    assert {:error, %Ash.Error.Forbidden{}} = Health.watch(true, actor: user)

    assert :ok = Health.watch(false, actor: context.root)
    refute Health.watching?(actor: context.root)
  end

  test "a fault alerts on each channel of each root user who watches, with no detail", context do
    :ok = Health.watch(true, actor: context.root)
    device!(context.root)
    {:ok, _topic} = Notifications.start_ntfy(actor: context.root)

    # A root user who does not watch hears nothing.
    device!(root!())

    now = DateTime.utc_now()
    fail!(context, now)
    assert Alerts.send_due(now) == 2
    work!()

    sends = sent()

    assert Enum.map(sends, &elem(&1, 0)) |> Enum.sort() == [
             "fcm.googleapis.com",
             "ntfy.example.org"
           ]

    {_host, headers, body} = Enum.find(sends, &(elem(&1, 0) == "ntfy.example.org"))
    assert body == "A sanity check of the server found a fault."
    assert headers["title"] == "Rescord"
    assert headers["click"] =~ ~r{/root/health$}

    # Nothing that names a check goes out.
    assert Alerts.message().body =~ "fault"
    refute Alerts.message().body =~ "root"
  end

  test "an alert comes once a day while the fault stays, and at once after a pass", context do
    :ok = Health.watch(true, actor: context.root)
    {:ok, _topic} = Notifications.start_ntfy(actor: context.root)
    now = DateTime.utc_now()

    fail!(context, now)
    assert Alerts.send_due(now) > 0
    work!()
    assert length(sent()) == 1

    # The next hour, the fault stays: no alert.
    later = DateTime.add(now, 1, :hour)
    fail!(context, later)
    assert Alerts.send_due(later) == 0

    # A day on, it still fails: one more.
    next_day = DateTime.add(now, 25, :hour)
    fail!(context, next_day)
    assert Alerts.send_due(next_day) > 0
    work!()
    assert length(sent()) == 1

    # It passes, and fails again within the day: at once.
    pass!(context, DateTime.add(next_day, 1, :hour))
    again = DateTime.add(next_day, 2, :hour)
    fail!(context, again)
    assert Alerts.send_due(again) > 0
  end

  test "with nobody who watches, a fault waits for the first person who does", context do
    now = DateTime.utc_now()
    fail!(context, now)
    assert Alerts.send_due(now) == 0

    :ok = Health.watch(true, actor: context.root)
    later = DateTime.add(now, 1, :hour)
    fail!(context, later)
    assert Alerts.send_due(later) > 0
  end

  test "a person who is no root user now gets no alert", context do
    :ok = Health.watch(true, actor: context.root)
    {:ok, _topic} = Notifications.start_ntfy(actor: context.root)

    # The person stops being a root user, and keeps the row.
    Repo.query!("update users set is_root = false where id = $1", [
      Ecto.UUID.dump!(context.root.id)
    ])

    now = DateTime.utc_now()
    fail!(context, now)
    assert Alerts.send_due(now) == 0
    work!()
    assert sent() == []
  end
end
