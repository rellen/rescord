defmodule Rescord.NotificationsTest do
  @moduledoc """
  Holds the notifications of the comments (issue 29, ADR 0106): who gets
  one, what leaves the server on each channel, the choices of a person,
  the devices and topics of a person, and how long a notification stays.

  The listener of `:commented` and the delivery run in jobs, which
  `Oban.drain_queue/1` runs in the process of the test. Each channel sends
  to a stub of `Req.Test`, so no test reaches a push service or ntfy.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Comments, Expenses, Notifications}
  alias Rescord.Notifications.{Notification, WebPush}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, sam} = member!(organisation, :member, administrator)
    {_, kim} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]

    Req.Test.set_req_test_to_shared()
    on_exit(&Req.Test.set_req_test_to_private/0)
    test = self()

    Req.Test.stub(Rescord.Notifications.Channel, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:sent, conn.host, conn.request_path, Map.new(conn.req_headers), body})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     sam: sam,
     kim: kim,
     lists: lists,
     admin: admin,
     hazel: resident!(lists, admin, %{name: "Hazel"})}
  end

  defp as(context, user), do: [actor: user, tenant: context.organisation]

  defp work!, do: Oban.drain_queue(queue: :default, with_recursion: true, with_safety: false)

  defp write!(context, user, fields, subject \\ nil) do
    {:ok, comment} =
      Comments.write(subject || {:resident, context.hazel.id}, fields, as(context, user))

    work!()
    comment
  end

  defp kinds(context, user) do
    {:ok, notifications} = Notifications.notifications(as(context, user))
    Enum.map(notifications, & &1.kind)
  end

  defp channels_on!(context, fields \\ %{}) do
    {:ok, _} = Notifications.make_keys(actor: context.root)

    {:ok, settings} =
      Notifications.save_settings(
        Map.merge(
          %{
            contact: "mailto:ops@example.org",
            push_on: true,
            ntfy_url: "https://ntfy.example.org",
            ntfy_on: true
          },
          fields
        ),
        actor: context.root
      )

    settings
  end

  defp device!(_context, user, endpoint \\ "https://fcm.googleapis.com/fcm/send/one") do
    keys = WebPush.keys()

    {:ok, device} =
      Notifications.subscribe_device(
        %{
          endpoint: endpoint,
          device_key: WebPush.encode(keys.public),
          auth: WebPush.encode(:crypto.strong_rand_bytes(16)),
          device: :android
        },
        actor: user
      )

    device
  end

  describe "a new comment" do
    test "notifies each follower and each person told, and not the writer", context do
      {:ok, _} = Comments.follow({:resident, context.hazel.id}, context.admin)
      write!(context, context.sam, %{body: "She limps.", told_ids: [context.kim.id]})

      assert kinds(context, context.kim) == [:told]
      assert kinds(context, context.administrator) == [:comment]
      assert kinds(context, context.sam) == []

      # The writer and the person told follow from now on.
      write!(context, context.administrator, %{body: "The vet comes at 3."})
      assert kinds(context, context.sam) == [:comment]
      assert kinds(context, context.kim) == [:comment, :told]
    end

    test "notifies nobody who cannot read the record", context do
      expense =
        Expenses.submit_expense!(
          %{
            paid_by: :member,
            amount: "40.00",
            incurred_on: Accounts.today(context.organisation),
            payee: "Northside Vet Clinic",
            description: "Worming tablets",
            category_id: context.lists.expense_category.veterinary
          },
          as(context, context.sam)
        )

      {:ok, _} = Comments.follow({:expense, expense.id}, as(context, context.sam))

      write!(
        context,
        context.administrator,
        %{body: "Approved.", told_ids: [context.kim.id]},
        {:expense, expense.id}
      )

      assert kinds(context, context.sam) == [:comment]
      # Kim is a member, but reads only her own expenses.
      assert kinds(context, context.kim) == []
    end

    test "is new until the person opens the record, or marks all as read", context do
      write!(context, context.sam, %{body: "One", told_ids: [context.kim.id]})
      kim = as(context, context.kim)
      assert Notifications.unread_count(kim) == 1

      :ok = Notifications.mark_read_on({:resident, context.hazel.id}, kim)
      assert Notifications.unread_count(kim) == 0

      write!(context, context.sam, %{body: "Two"})
      assert Notifications.unread_count(kim) == 1
      :ok = Notifications.mark_all_read(kim)
      assert Notifications.unread_count(kim) == 0
    end

    test "a person reads only their own notifications", context do
      write!(context, context.sam, %{body: "One", told_ids: [context.kim.id]})
      [notification] = Ash.read!(Notification, tenant: context.organisation, authorize?: false)

      assert {:error, _} = Notifications.mark_read(notification, as(context, context.sam))

      assert {:ok, %{read_at: %DateTime{}}} =
               Notifications.mark_read(notification, as(context, context.kim))
    end
  end

  describe "Web Push" do
    test "sends a pointer, encrypted, signed by the server, to the device", context do
      channels_on!(context)
      device!(context, context.kim)
      write!(context, context.sam, %{body: "Hazel ate it all.", told_ids: [context.kim.id]})

      assert_received {:sent, "fcm.googleapis.com", "/fcm/send/one", headers, body}
      assert "vapid t=" <> _ = headers["authorization"]
      # The stub of Req takes `content-encoding` off a request before the plug
      # sees it, so the test cannot read it here.
      assert headers["ttl"]
      refute body =~ "Hazel"

      [notification] = Ash.read!(Notification, tenant: context.organisation, authorize?: false)
      assert :web_push in notification.delivered
      assert notification.delivered_at

      [device] = Notifications.devices(actor: context.kim)
      assert device.last_sent_at
      assert device.id
    end

    test "forgets a device that the push service says is gone", context do
      channels_on!(context, %{ntfy_on: false})
      device!(context, context.kim)

      Req.Test.stub(Rescord.Notifications.Channel, &Plug.Conn.send_resp(&1, 410, ""))
      write!(context, context.sam, %{body: "One", told_ids: [context.kim.id]})

      assert Notifications.devices(actor: context.kim) == []
    end

    test "tries again later when the push service is busy", context do
      channels_on!(context, %{ntfy_on: false})
      device!(context, context.kim)

      Req.Test.stub(Rescord.Notifications.Channel, &Plug.Conn.send_resp(&1, 503, ""))

      {:ok, _} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "One", told_ids: [context.kim.id]},
          as(context, context.sam)
        )

      # The listener and the first try; the next try is an hour away.
      Oban.drain_queue(queue: :default, with_safety: false)
      Oban.drain_queue(queue: :default, with_safety: false)

      [notification] = Ash.read!(Notification, tenant: context.organisation, authorize?: false)
      assert notification.tries == 1
      assert notification.delivered == []
      assert is_nil(notification.delivered_at)
    end

    test "sends nothing while the server has it off", context do
      channels_on!(context, %{push_on: false, ntfy_on: false})
      device!(context, context.kim)
      write!(context, context.sam, %{body: "One", told_ids: [context.kim.id]})

      refute_received {:sent, _, _, _, _}
      assert kinds(context, context.kim) == [:told]
    end

    test "takes only the address of a push service of a browser", context do
      assert {:error, %Ash.Error.Invalid{}} =
               Notifications.subscribe_device(
                 %{
                   endpoint: "https://evil.example.org/collect",
                   device_key: WebPush.encode(WebPush.keys().public),
                   auth: WebPush.encode(:crypto.strong_rand_bytes(16)),
                   device: :android
                 },
                 actor: context.kim
               )
    end

    test "a person reads and removes no device of another", context do
      device = device!(context, context.kim)

      assert Notifications.devices(actor: context.sam) == []
      assert Notifications.device(device.id, actor: context.sam) == nil
      assert {:error, _} = Notifications.remove_device(device, actor: context.sam)
      assert :ok = Notifications.remove_device(device, actor: context.kim)
      assert Notifications.devices(actor: context.kim) == []
    end

    test "new keys end each device", context do
      channels_on!(context)
      device!(context, context.kim)
      {:ok, _} = Notifications.make_keys(actor: context.root)
      assert Notifications.device_count() == 0
    end
  end

  describe "ntfy" do
    test "sends the name of the refuge, one sentence and a link, to the topic of the person",
         context do
      channels_on!(context, %{push_on: false})
      {:ok, _} = Notifications.start_ntfy(actor: context.kim)
      address = Notifications.ntfy_address(actor: context.kim)
      "https://ntfy.example.org/" <> topic = address
      assert String.length(topic) >= 32

      write!(context, context.sam, %{body: "Hazel ate it all.", told_ids: [context.kim.id]})

      assert_received {:sent, "ntfy.example.org", "/" <> ^topic, headers, body}
      assert headers["title"] == "Wattle Creek"
      assert headers["click"] =~ "/o/#{context.organisation.short_name}/notifications"
      assert body == "Somebody told you about a comment."
      refute body =~ "Hazel"
    end

    test "a new address stops the old one, and a stop ends it", context do
      channels_on!(context, %{push_on: false})
      {:ok, topic} = Notifications.start_ntfy(actor: context.kim)
      old = Notifications.ntfy_address(actor: context.kim)

      {:ok, topic} = Notifications.renew_ntfy(topic, actor: context.kim)
      assert Notifications.ntfy_address(actor: context.kim) != old

      assert {:error, _} = Notifications.stop_ntfy(topic, actor: context.sam)
      assert :ok = Notifications.stop_ntfy(topic, actor: context.kim)
      assert Notifications.ntfy_address(actor: context.kim) == nil
    end
  end

  describe "the choices of a person" do
    test "a kind of notification goes only to the channels that the person chose", context do
      channels_on!(context, %{push_on: false})
      {:ok, _} = Notifications.start_ntfy(actor: context.kim)
      {:ok, _} = Notifications.set_preference(:told, [], as(context, context.kim))

      write!(context, context.sam, %{body: "One", told_ids: [context.kim.id]})
      refute_received {:sent, _, _, _, _}
      # It is on the page in any case.
      assert kinds(context, context.kim) == [:told]

      assert Notifications.preferences(as(context, context.kim)) == %{
               told: [],
               comment: [:web_push, :ntfy]
             }
    end
  end

  describe "the settings of the server" do
    test "only a root user reads or changes them, and no page reads the private key", context do
      assert {:error, _} =
               Notifications.save_settings(%{push_on: true}, actor: context.administrator)

      settings = channels_on!(context)
      assert settings.vapid_public_key
      refute Map.get(settings, :vapid_private_key) |> is_binary()

      assert Notifications.offer() == %{web_push: settings.vapid_public_key, ntfy: true}
    end

    test "refuse a channel that cannot work", context do
      assert {:error, %Ash.Error.Invalid{}} =
               Notifications.save_settings(%{push_on: true}, actor: context.root)

      assert {:error, %Ash.Error.Invalid{}} =
               Notifications.save_settings(%{ntfy_url: "http://ntfy.example.org"},
                 actor: context.root
               )

      assert {:error, %Ash.Error.Invalid{}} =
               Notifications.save_settings(%{contact: "ops@example.org"}, actor: context.root)
    end

    test "keep the token of ntfy, and send it", context do
      channels_on!(context, %{push_on: false})
      assert {:ok, _} = Notifications.save_ntfy_token("tk_secret", actor: context.root)
      {:ok, _} = Notifications.start_ntfy(actor: context.kim)

      write!(context, context.sam, %{body: "One", told_ids: [context.kim.id]})
      assert_received {:sent, "ntfy.example.org", _path, headers, _body}
      assert headers["authorization"] == "Bearer tk_secret"
    end
  end

  describe "an old notification" do
    test "goes 30 days after it was read, and after 90 days in any case", context do
      write!(context, context.sam, %{body: "One", told_ids: [context.kim.id]})
      now = DateTime.utc_now()

      :ok = Notifications.prune(context.organisation, DateTime.add(now, 29, :day))
      assert kinds(context, context.kim) == [:told]

      :ok = Notifications.mark_all_read(as(context, context.kim))
      :ok = Notifications.prune(context.organisation, DateTime.add(now, 31, :day))
      assert kinds(context, context.kim) == []

      write!(context, context.sam, %{body: "Two"})
      :ok = Notifications.prune(context.organisation, DateTime.add(now, 91, :day))
      assert kinds(context, context.kim) == []
    end
  end
end
