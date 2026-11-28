defmodule Rescord.CalendarsTest do
  @moduledoc """
  Holds the calendar feeds of an organisation (ADR 0074): who makes a feed
  and who reads and revokes it, the token that Rescord shows one time and
  stores as a hash, each way that a feed stops, and what the calendar of a
  feed holds.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Calendars, Inventory, Locations, Residents, Tasks}
  alias Rescord.Calendars.{Feed, Token}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {member, user} = member!(organisation, :member, administrator)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     user: user,
     today: Accounts.today(organisation),
     admin: [actor: administrator, tenant: organisation],
     options: [actor: user, tenant: organisation]}
  end

  defp feed!(context, attributes \\ %{}, options \\ nil) do
    Calendars.subscribe!(Map.merge(%{name: "My phone"}, attributes), options || context.options)
  end

  # A role with the powers of `powers`, and the member of the context in it.
  defp give_role!(context, name, powers) do
    {:ok, role} = Accounts.define_role(%{name: name, powers: powers}, context.admin)
    {:ok, _member} = Accounts.set_member_role(context.member, role.id, context.admin)
    role
  end

  # The instant of a time of a day of the organisation.
  defp at(context, days, time \\ "09:00") do
    day = Date.add(context.today, days)

    {:ok, instant} =
      Accounts.local_instant(context.organisation, "#{Date.to_iso8601(day)}T#{time}")

    instant
  end

  defp task!(context, title, days, more \\ %{}) do
    Tasks.plan_task!(Map.merge(%{title: title, due_at: at(context, days)}, more), context.admin)
  end

  defp titles(entries), do: for(%{kind: :task, record: task} <- entries, do: task.title)

  defp entries!(context, feed, user \\ nil) do
    {:ok, entries} = Calendars.entries(feed, user || context.user, context.organisation)
    entries
  end

  defp rows(context, table) do
    Repo.query!(~s(select * from "org_#{context.organisation.id}"."#{table}")).rows
  end

  describe "a feed" do
    test "is made by a member for themselves, with a token that Rescord shows one time",
         context do
      feed = feed!(context, %{tasks: :all, with_returns: true})
      token = Calendars.token(feed)

      assert Token.shape?(token)
      assert String.length(token) == 43
      assert feed.member_id == context.member.id
      assert feed.owner_id == context.user.id
      assert %{tasks: :all, with_returns: true, with_expiry: false, with_notes: false} = feed
      assert is_nil(feed.last_fetched_at)

      # A read of the feed has no token: Rescord stores its hash alone.
      assert {:ok, [read]} = Calendars.feeds_of(context.user, context.options)
      assert read.id == feed.id
      assert is_nil(Calendars.token(read))

      stored = inspect(rows(context, "calendar_feeds"))
      refute stored =~ token
      assert stored =~ Token.hash(token)

      # A version holds neither the token nor its hash.
      versions = inspect(rows(context, "calendar_feeds_versions"))
      assert versions =~ "subscribe"
      refute versions =~ token
      refute versions =~ Token.hash(token)
    end

    test "has a token of its own", context do
      tokens = for _ <- 1..3, do: Calendars.token(feed!(context))
      assert length(Enum.uniq(tokens)) == 3
    end

    test "takes no owner as input", context do
      for input <- [:owner_id, :member_id, :token_hash] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Calendars.subscribe(
                   %{name: "My phone"} |> Map.put(input, context.administrator.id),
                   context.options
                 )
      end
    end

    test "holds one part at least, and has a name", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Calendars.subscribe(%{name: "Empty", tasks: :none}, context.options)

      assert Enum.any?(Accounts.error_messages(error), &(&1 =~ "the feed would be empty"))

      assert {:ok, _feed} =
               Calendars.subscribe(
                 %{name: "Stock", tasks: :none, with_expiry: true},
                 context.options
               )

      assert {:error, %Ash.Error.Invalid{}} = Calendars.subscribe(%{tasks: :all}, context.options)
    end

    test "is one of 10 at most for a member", context do
      limit = Calendars.feeds_for_each_member()
      assert limit == 10

      feeds = for number <- 1..limit, do: feed!(context, %{name: "Feed #{number}"})

      assert {:error, %Ash.Error.Invalid{} = error} =
               Calendars.subscribe(%{name: "One more"}, context.options)

      assert Enum.any?(Accounts.error_messages(error), &(&1 =~ "Revoke one first"))

      # A revoked feed does not count.
      :ok = Calendars.revoke_feed(hd(feeds), context.options)
      assert {:ok, _feed} = Calendars.subscribe(%{name: "One more"}, context.options)

      # The feeds of another member do not count.
      assert {:ok, _feed} = Calendars.subscribe(%{name: "Mine"}, context.admin)
    end

    test "belongs to a member: a root user who is not one gets none", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Calendars.subscribe(%{name: "Root"},
                 actor: context.root,
                 tenant: context.organisation
               )

      assert Enum.any?(Accounts.error_messages(error), &(&1 =~ "only a member"))
    end

    test "needs the power calendar", context do
      feed = feed!(context)
      give_role!(context, "Feeder", [:tasks])

      assert {:error, %Ash.Error.Forbidden{}} =
               Calendars.subscribe(%{name: "Another"}, context.options)

      # Without the power the person reads no feed, and revokes none.
      assert {:ok, []} = Calendars.feeds_of(context.user, context.options)
      assert {:error, %Ash.Error.Forbidden{}} = Calendars.revoke_feed(feed, context.options)

      refute Calendars.role_can?(
               Accounts.Checks.Granted.role_of(context.user, context.organisation),
               :subscribe
             )
    end

    test "is read and revoked by its owner, and not by another member", context do
      mine = feed!(context)
      theirs = feed!(context, %{name: "The office"}, context.admin)
      {_, other} = member!(context.organisation, :member, context.administrator)
      other_options = [actor: other, tenant: context.organisation]

      assert {:ok, [%{id: id}]} = Calendars.feeds_of(context.user, context.options)
      assert id == mine.id

      # A member reads no feed of another person, whatever the question is.
      assert {:ok, []} = Calendars.feeds_of_others(context.user, context.options)
      assert {:ok, []} = Calendars.feeds_of(context.user, other_options)
      assert {:ok, [%{id: ^id}]} = Calendars.feeds(context.options)

      assert {:error, %Ash.Error.Forbidden{}} = Calendars.revoke_feed(theirs, context.options)
      assert {:error, %Ash.Error.Forbidden{}} = Calendars.revoke_feed(mine, other_options)

      assert :ok = Calendars.revoke_feed(mine, context.options)
      assert {:ok, []} = Calendars.feeds_of(context.user, context.options)
    end

    test "of each member is read and revoked by a person with the power members", context do
      mine = feed!(context)

      assert {:ok, [feed]} = Calendars.feeds_of_others(context.administrator, context.admin)
      assert feed.id == mine.id
      assert to_string(feed.member.email) == to_string(context.user.email)
      assert is_nil(Calendars.token(feed))

      administrator = Accounts.Checks.Granted.role_of(context.administrator, context.organisation)
      member = Accounts.Checks.Granted.role_of(context.user, context.organisation)
      assert Calendars.role_reads_each?(administrator)
      assert Calendars.role_reads_each?(:root)
      refute Calendars.role_reads_each?(member)

      assert :ok = Calendars.revoke_feed(mine, context.admin)
      assert {:ok, []} = Calendars.feeds_of_others(context.administrator, context.admin)
    end

    test "that is revoked keeps its row and its history, and loses its hash", context do
      feed = feed!(context)
      token = Calendars.token(feed)

      assert :ok = Calendars.revoke_feed(feed, context.options)

      assert [row] = rows(context, "calendar_feeds")
      refute inspect(row) =~ Token.hash(token)
      assert inspect(rows(context, "calendar_feeds_versions")) =~ "revoke"
      assert Ash.read!(Feed, tenant: context.organisation, authorize?: false) == []
    end
  end

  describe "the token of a feed" do
    test "finds the feed, the user that it reads as and the organisation", context do
      feed = feed!(context)
      short_name = context.organisation.short_name

      assert {:ok, found, user, organisation} = Calendars.fetch(short_name, Calendars.token(feed))
      assert found.id == feed.id
      assert user.id == context.user.id
      assert organisation.id == context.organisation.id
    end

    test "finds nothing in another organisation, and nothing for a text that is no token",
         context do
      feed = feed!(context)
      token = Calendars.token(feed)
      other = organisation!(context.root, "Banksia Rise")

      assert Calendars.fetch(other.short_name, token) == :error
      assert Calendars.fetch("no-such-refuge", token) == :error
      assert Calendars.fetch(context.organisation.short_name, Token.new()) == :error
      assert Calendars.fetch(context.organisation.short_name, token <> "a") == :error
      assert Calendars.fetch(context.organisation.short_name, "") == :error
      assert Calendars.fetch(context.organisation.short_name, nil) == :error
      assert Calendars.fetch(nil, token) == :error

      # The hash of a token is no token.
      assert Calendars.fetch(context.organisation.short_name, Token.hash(token)) == :error
    end

    test "finds nothing after the feed is revoked", context do
      feed = feed!(context)
      token = Calendars.token(feed)
      short_name = context.organisation.short_name

      assert {:ok, _feed, _user, _organisation} = Calendars.fetch(short_name, token)
      assert :ok = Calendars.revoke_feed(feed, context.options)
      assert Calendars.fetch(short_name, token) == :error
    end

    test "finds nothing after the member is removed, and nothing when they come back",
         context do
      token = Calendars.token(feed!(context))
      short_name = context.organisation.short_name

      assert :ok = Accounts.remove_member(context.member, context.admin)
      assert Calendars.fetch(short_name, token) == :error

      # A new invitation makes a new member. The old feed stays dead.
      {again, user} =
        member!(
          context.organisation,
          :member,
          context.administrator,
          to_string(context.user.email)
        )

      assert user.id == context.user.id
      assert again.id != context.member.id
      assert Calendars.fetch(short_name, token) == :error

      # And the new member does not see it.
      assert {:ok, []} = Calendars.feeds_of(user, actor: user, tenant: context.organisation)
      assert {:ok, []} = Calendars.feeds_of_others(context.administrator, context.admin)
    end

    test "finds nothing while the role of the owner cannot make a feed", context do
      token = Calendars.token(feed!(context))
      short_name = context.organisation.short_name

      feeder = give_role!(context, "Feeder", [:tasks])
      assert Calendars.fetch(short_name, token) == :error

      # The power `members` reads the feeds, and makes none.
      {:ok, _role} = Accounts.revise_role(feeder, %{powers: [:tasks, :members]}, context.admin)
      assert Calendars.fetch(short_name, token) == :error

      {:ok, _role} = Accounts.revise_role(feeder, %{powers: [:tasks, :calendar]}, context.admin)
      assert {:ok, _feed, _user, _organisation} = Calendars.fetch(short_name, token)
    end

    test "says when a calendar app read the feed, once an hour at most", context do
      feed = feed!(context)
      token = Calendars.token(feed)
      short_name = context.organisation.short_name
      first = ~U[2026-11-28 05:00:00Z]

      assert {:ok, %{last_fetched_at: ^first}, _, _} = Calendars.fetch(short_name, token, first)

      later = DateTime.add(first, 59 * 60)
      assert {:ok, %{last_fetched_at: ^first}, _, _} = Calendars.fetch(short_name, token, later)

      next = DateTime.add(first, 60 * 60)
      assert {:ok, %{last_fetched_at: ^next}, _, _} = Calendars.fetch(short_name, token, next)

      # The owner reads it, and the mark has no version.
      assert {:ok, [%{last_fetched_at: ^next}]} =
               Calendars.feeds_of(context.user, context.options)

      refute inspect(rows(context, "calendar_feeds_versions")) =~ "mark"
    end
  end

  describe "the calendar of a feed" do
    test "holds the tasks that the feed names", context do
      task!(context, "Mine", 1, %{assignee_ids: [context.user.id]})
      task!(context, "Shared", 1, %{assignee_ids: [context.user.id, context.administrator.id]})
      task!(context, "For anybody", 1)
      task!(context, "Theirs", 1, %{assignee_ids: [context.administrator.id]})

      for {choice, expected} <- [
            mine: ["Mine", "Shared"],
            mine_and_open: ["For anybody", "Mine", "Shared"],
            all: ["For anybody", "Mine", "Shared", "Theirs"]
          ] do
        feed = feed!(context, %{name: "Feed #{choice}", tasks: choice})
        assert Enum.sort(titles(entries!(context, feed))) == expected
      end

      none = feed!(context, %{name: "Stock", tasks: :none, with_expiry: true})
      assert entries!(context, none) == []
    end

    test "holds a task as an entry at its time, with its kind and its subjects", context do
      lists = lists!(context.organisation, context.root)
      biscuit = resident!(lists, context.admin)

      task =
        task!(context, "Morning feed", 2, %{
          kind_id: lists.task_kind.feed,
          resident_ids: [biscuit.id]
        })

      feed = feed!(context, %{tasks: :all})
      assert [%{kind: :task, record: record, at: at}] = entries!(context, feed)

      assert record.id == task.id
      assert at == task.due_at
      assert to_string(record.kind.label) == "Feed"
      assert Tasks.subject_names(record) == ["Biscuit"]
    end

    test "holds what is dated from 7 days before today, in the order of the time", context do
      assert Calendars.days_back() == 7

      task!(context, "Too old", -8)
      task!(context, "A week ago", -7)
      task!(context, "Months ahead", 200)
      task!(context, "Today", 0)
      done = task!(context, "Done yesterday", -1)
      {:ok, _done} = Tasks.complete_task(done, %{}, context.options)

      feed = feed!(context, %{tasks: :all})
      entries = entries!(context, feed)

      assert titles(entries) == ["A week ago", "Done yesterday", "Today", "Months ahead"]
      assert Enum.find(entries, &(&1.record.title == "Done yesterday")).record.state == :done
    end

    test "holds the day that a resident that is away is expected back", context do
      lists = lists!(context.organisation, context.root)

      [fern, hazel, juniper, sage] =
        for name <- ~w(Fern Hazel Juniper Sage),
            do: resident!(lists, context.admin, %{name: name})

      for {resident, days} <- [{fern, 3}, {hazel, -9}, {juniper, nil}, {sage, 5}] do
        {:ok, _absence} =
          Residents.start_absence(
            %{
              resident_id: resident.id,
              reason: "At the clinic",
              expected_back_on: days && Date.add(context.today, days)
            },
            context.admin
          )
      end

      # A resident that left is not away, whatever its absence says.
      {:ok, _departure} =
        Residents.record_departure(
          %{resident_id: sage.id, kind: :death, departed_on: context.today},
          context.admin
        )

      with_returns = feed!(context, %{tasks: :none, with_returns: true})
      day = Date.add(context.today, 3)

      assert [%{kind: :return, record: %{name: "Fern"}, absence: absence, on: ^day}] =
               entries!(context, with_returns)

      assert absence.reason == "At the clinic"

      without = feed!(context, %{name: "Tasks", tasks: :all})
      assert entries!(context, without) == []
    end

    test "holds the expiry date of each lot that has stock", context do
      lists = lists!(context.organisation, context.root)
      shed = Locations.add_location!(%{name: "Feed shed"}, context.admin)
      hay = Inventory.add_item!(%{name: "Meadow hay", unit_id: lists.unit.bag}, context.admin)

      lot = fn code, days, quantity ->
        Inventory.receive_lot!(
          %{
            item_id: hay.id,
            code: code,
            quantity: quantity,
            location_id: shed.id,
            expires_on: days && Date.add(context.today, days)
          },
          context.admin
        )
      end

      lot.("SOON", 20, 10)
      lot.("LATER", 90, 4)
      lot.("OLD", -30, 2)
      lot.("NO-DATE", nil, 3)
      empty = lot.("EMPTY", 40, 5)

      {:ok, _movement} =
        Inventory.use_stock(
          %{lot_id: empty.id, location_id: shed.id, quantity: 5},
          context.admin
        )

      feed = feed!(context, %{tasks: :none, with_expiry: true})
      entries = entries!(context, feed)

      assert Enum.map(entries, &{&1.kind, &1.lot.code, Date.diff(&1.on, context.today)}) == [
               {:expiry, "SOON", 20},
               {:expiry, "LATER", 90}
             ]

      assert [%{record: %{name: "Meadow hay"}, level: level} | _] = entries
      assert Decimal.equal?(level, 10)
    end

    test "puts a day at its start, among the tasks", context do
      lists = lists!(context.organisation, context.root)
      fern = resident!(lists, context.admin, %{name: "Fern"})

      {:ok, _absence} =
        Residents.start_absence(
          %{
            resident_id: fern.id,
            reason: "At the clinic",
            expected_back_on: Date.add(context.today, 2)
          },
          context.admin
        )

      task!(context, "The day before", 1)
      task!(context, "That morning", 2)

      feed = feed!(context, %{tasks: :all, with_returns: true})

      assert Enum.map(entries!(context, feed), & &1.kind) == [:task, :return, :task]
    end

    test "is read as the user: a person who reads nothing gets nothing", context do
      task!(context, "For anybody", 1)
      feed = feed!(context, %{tasks: :all})

      assert [_task] = entries!(context, feed)

      # A user of another refuge reads no record of this one.
      other = organisation!(context.root, "Banksia Rise")
      {_, stranger} = member!(other, :administrator, context.root)
      assert entries!(context, feed, stranger) == []
    end
  end
end
