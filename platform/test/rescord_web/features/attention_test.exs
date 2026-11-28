defmodule RescordWeb.Features.AttentionTest do
  @moduledoc """
  Holds the first page of an organisation in a real browser (ADR 0065), with
  the screen of a phone (ADR 0061): what a page test cannot see.

    * With a row of each kind, and long names, the page is not wider than
      a screen of 320px, and each row is as high as a finger.
    * A finger presses a row anywhere, and not only the words of its link.
    * The row of a task opens the page of the tasks at that task, in view
      below the site bar.
    * The keyboard reaches each row, and the focus shows around the row.
    * On a wide screen the page keeps the same order, and is no wider.

  The test creates organisations, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Inventory, Locations, Residents, Tasks, Transfers}

  # A long address, and not the one of `PhoneTest`: an address gets five
  # sign-in links in a quarter of an hour (ADR 0020), and one run of the
  # tests has both.
  @address "a.carer.with.a.long.address.of.their.own@wattle-creek-refuge.example.org"

  @small [viewport: %{width: 320, height: 640}, has_touch: true]
  @phone [viewport: %{width: 360, height: 780}, has_touch: true]

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek Small Animal Refuge")
    {_member, user} = member!(organisation, :administrator, root, @address)
    lists = lists!(organisation, root)
    options = [actor: root, tenant: organisation]
    today = Accounts.today(organisation)
    yesterday = Date.add(today, -1)

    reginald = resident!(lists, options, %{name: "Sir Reginald Fluffington the Third"})

    {:ok, due_at} = Accounts.local_instant(organisation, "#{Date.to_iso8601(yesterday)}T18:30")

    task =
      Tasks.plan_task!(
        %{
          title: "Give Sir Reginald Fluffington the Third his evening medication with food",
          due_at: due_at,
          kind_id: lists.task_kind.medicate,
          resident_ids: [reginald.id],
          assignee_ids: [user.id]
        },
        options
      )

    {:ok, later} = Accounts.local_instant(organisation, "#{Date.to_iso8601(today)}T23:59")
    Tasks.plan_task!(%{title: "Evening feed", due_at: later}, options)

    hay =
      Inventory.add_item!(
        %{name: "Meadow hay", unit_id: lists.unit.bag, reorder_level: 20},
        options
      )

    shed = Locations.add_location!(%{name: "Feed shed"}, options)

    lot =
      Inventory.receive_lot!(
        %{item_id: hay.id, quantity: 2, location_id: shed.id, expires_on: Date.add(today, 5)},
        options
      )

    {:ok, _} =
      Inventory.use_stock(%{lot_id: lot.id, location_id: shed.id, quantity: 3}, options)

    resident!(lists, options, %{name: "Clover", arrival_kind: nil, arrived_on: nil})

    {:ok, _} =
      Residents.start_absence(
        %{
          resident_id: reginald.id,
          reason: "At the clinic of the veterinarian in the next town, for an operation",
          expected_back_on: yesterday
        },
        options
      )

    pen = Locations.add_location!(%{name: "East 1", capacity: 1}, options)

    for name <- ["Fern", "Hazel"] do
      resident = resident!(lists, options, %{name: name})
      {:ok, _} = Locations.settle({:resident, resident.id}, pen.id, options)
    end

    banksia = organisation!(root, "Banksia Rise Rabbit and Guinea Pig Sanctuary")
    {:ok, _} = Transfers.ask_partner(banksia, organisation.short_name, actor: root)

    # The email of the invitation is not what the test looks at.
    flush_emails()

    {:ok, home: "/o/#{organisation.short_name}", task: task}
  end

  @tag browser_context_opts: @small
  test "on a small phone the page is no wider than the screen, and a row takes a finger",
       %{conn: session, home: home} do
    session
    |> sign_in_with_link(@address)
    |> visit(home)
    |> assert_connected()
    |> assert_has("#attention-summary", text: "7 things need attention now.")
    # A row of each kind is there.
    |> assert_has("#attention-tasks li", count: 2)
    |> assert_has("#attention-inventory li", text: "Meadow hay")
    |> assert_has("#attention-residents li", count: 2)
    |> assert_has("#attention-housing li", text: "East 1")
    |> assert_has("#attention-transfers li", text: "Banksia Rise")
    |> evaluate(
      """
      (() => {
        const root = document.documentElement;
        const rows = Array.from(document.querySelectorAll("ul[data-attention] > li"));
        return {
          wider: root.scrollWidth - root.clientWidth,
          low: rows.filter((row) => row.getBoundingClientRect().height < 43.5).length,
          outside: Array.from(document.querySelectorAll("#attention *")).filter((element) => {
            const box = element.getBoundingClientRect();
            return box.width > 0 && (box.left < 0 || box.right > root.clientWidth + 1);
          }).map((element) => element.tagName + " " + element.innerText.slice(0, 30)),
          // The link fills its row: a press at each corner of a row finds it.
          missed: rows.filter((row) => {
            const box = row.getBoundingClientRect();
            row.scrollIntoView({ block: "center" });
            const now = row.getBoundingClientRect();
            const link = row.querySelector("a");
            return [[now.left + 3, now.top + 3], [now.right - 3, now.bottom - 3]]
              .some(([x, y]) => document.elementFromPoint(x, y) !== link) || box.width === 0;
          }).length
        };
      })()
      """,
      fn page ->
        assert page["wider"] == 0, "the page is #{page["wider"]}px wider than the phone"
        assert page["low"] == 0, "#{page["low"]} rows are lower than a finger"
        assert page["outside"] == []
        assert page["missed"] == 0, "a press on #{page["missed"]} rows misses the link"
      end
    )
  end

  @tag browser_context_opts: @phone
  test "a press on the row of a task opens the tasks at that task",
       %{conn: session, home: home, task: task} do
    session
    |> sign_in_with_link(@address)
    |> visit(home)
    |> assert_connected()
    |> assert_has("#attention-task-#{task.id} span[data-state=alert]", text: "Overdue")
    # The press is at the end of the row, far from the words of the link.
    |> evaluate("""
    (() => {
      const box = document.querySelector("#attention-task-#{task.id}").getBoundingClientRect();
      document.elementFromPoint(box.right - 4, box.bottom - 4).click();
    })()
    """)
    |> assert_has("h1", text: "Tasks", exact: true)
    |> assert_connected()
    |> assert_has("#task-#{task.id}", text: "Give Sir Reginald")
    |> evaluate(
      """
      (async () => {
        await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
        const row = document.querySelector("#task-#{task.id}").getBoundingClientRect();
        const bar = document.querySelector("header").getBoundingClientRect();
        return { top: row.top, bar: bar.bottom, screen: window.innerHeight, hash: location.hash };
      })()
      """,
      fn place ->
        assert place["hash"] == "#task-#{task.id}"
        assert place["top"] >= place["bar"], "the task is below the site bar"
        assert place["top"] < place["screen"], "the task is not in the screen"
      end
    )
  end

  @tag browser_context_opts: [viewport: %{width: 1280, height: 800}]
  test "the keyboard reaches each row, and the focus shows around the row",
       %{conn: session, home: home, task: task} do
    session
    |> sign_in_with_link(@address)
    |> visit(home)
    |> assert_connected()
    |> evaluate(
      """
      (() => {
        const root = document.documentElement;
        const row = document.querySelector("#attention-task-#{task.id}");
        row.querySelector("a").focus({ focusVisible: true });
        const order = Array.from(document.querySelectorAll("main h2, main h3"))
          .map((heading) => heading.firstChild.textContent.trim());
        return {
          focused: document.activeElement === row.querySelector("a"),
          outline: getComputedStyle(row).outlineStyle,
          wider: root.scrollWidth - root.clientWidth,
          order: order
        };
      })()
      """,
      fn page ->
        assert page["focused"]
        assert page["outline"] == "solid", "the row of the focus has no outline"
        assert page["wider"] == 0

        assert page["order"] == [
                 "Needs attention",
                 "Tasks",
                 "Stock",
                 "Residents",
                 "Housing",
                 "Transfers and partners",
                 "The parts of Wattle Creek Small Animal Refuge"
               ]
      end
    )
    |> press("#attention-task-#{task.id} a", "Enter")
    |> assert_has("h1", text: "Tasks", exact: true)
  end
end
