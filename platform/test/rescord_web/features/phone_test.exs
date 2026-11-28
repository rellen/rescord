defmodule RescordWeb.Features.PhoneTest do
  @moduledoc """
  Holds the pages to the rules of a phone, in a real browser (ADR 0061).

  A page test reads the markup, and the markup does not say how wide a page
  is, how high a button is, or if a menu is open. This test gives the
  browser the screen of a phone, and asks the browser:

    * no page is wider than a screen of 320px, and nothing in a page
      scrolls sideways;
    * each thing that a finger presses is 44px high or more, and the text
      of each control is 16px or more;
    * the site menu is closed at first, opens from its button, says the
      part that the page is in, and closes on the Escape key;
    * a table is a list of cards: the buttons of a row are in view, and a
      cell says its column;
    * on a wide screen the menu is in the page, in two rows.

  The administrator has a long address and the organisation a long name,
  because those are what broke the menu.

  The test creates an organisation, so it does not run beside others (see
  `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Inventory, Locations, Tasks}

  @address "an.administrator.with.a.long.address@wattle-creek-refuge.example.org"

  # The least screen that WCAG 1.4.10 asks for, and a common phone.
  @small [viewport: %{width: 320, height: 640}, has_touch: true]
  @phone [viewport: %{width: 360, height: 780}, has_touch: true]

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek Small Animal Refuge")
    {_member, user} = member!(organisation, :administrator, root, @address)
    lists = lists!(organisation, root)
    options = [actor: root, tenant: organisation]

    resident = resident!(lists, options, %{name: "Sir Reginald Fluffington the Third"})
    resident!(lists, options, %{name: "Clover", sex: :female})

    shed = Locations.add_location!(%{name: "Feed shed"}, options)
    hay = Inventory.add_item!(%{name: "Meadow hay", unit_id: lists.unit.bag}, options)

    Inventory.receive_lot!(
      %{item_id: hay.id, code: "B-1", quantity: 10, location_id: shed.id},
      options
    )

    {:ok, due_at} =
      Accounts.local_instant(
        organisation,
        "#{Date.to_iso8601(Accounts.today(organisation))}T23:30"
      )

    Tasks.plan_task!(
      %{
        title: "Give Sir Reginald his evening medication",
        due_at: due_at,
        kind_id: lists.task_kind.medicate,
        resident_ids: [resident.id],
        assignee_ids: [user.id],
        note: "With food"
      },
      options
    )

    # The email of the invitation is not what the test looks at.
    flush_emails()

    home = "/o/#{organisation.short_name}"

    {:ok,
     home: home,
     pages:
       ["/", home] ++
         Enum.map(
           ~w(tasks routines residents residents/new residents/#{resident.id}
              residents/#{resident.id}/edit residents/#{resident.id}/journal
              residents/#{resident.id}/photos residents/#{resident.id}/timeline groups housing
              housing/#{shed.id} inventory inventory/#{hay.id} inventory/suppliers tools tools/dose
              lists members roles partners transfers settings export calendar),
           &"#{home}/#{&1}"
         )}
  end

  @tag browser_context_opts: @small
  test "no page is wider than a small phone, and each control is large enough",
       %{conn: session, pages: pages} do
    session = sign_in_with_link(session, @address)

    for page <- pages do
      session
      |> visit(page)
      |> assert_has("h1")
      |> evaluate(problems(), fn problems ->
        assert problems == [], "#{page} on a phone: #{Enum.join(problems, "; ")}"
      end)
    end
  end

  @tag browser_context_opts: @small
  test "the pages of the assistant for a root user fit a small phone", %{conn: session} do
    address = "a.root.user.with.a.long.address@wattle-creek-refuge.example.org"
    root = root!(address)

    provider =
      Rescord.RubyFixtures.provider!(root, %{name: "Anthropic, for the whole server"})

    Rescord.Ruby.ScriptedModel.script([{:error, %{status: 401}}])
    {:ok, _provider} = Rescord.Ruby.test_provider(provider, actor: root)

    Rescord.RubyFixtures.provider!(root, %{
      name: "The server in the feed shed",
      kind: :openai_compatible,
      model: "a-model-with-a-long-name-of-its-own:32b-instruct",
      base_url: "https://llm.a-long-name-of-a-server.example.org/v1"
    })

    session = sign_in_with_link(session, address)

    pages = [
      "/root",
      "/root/ruby",
      "/root/ruby/new",
      "/root/ruby/new?kind=openai_compatible",
      "/root/ruby/#{provider.id}"
    ]

    for page <- pages do
      session
      |> visit(page)
      |> assert_has("h1")
      |> evaluate(problems(), fn problems ->
        assert problems == [], "#{page} on a phone: #{Enum.join(problems, "; ")}"
      end)
    end

    # The list is a card for each provider, and a cell says its column.
    session
    |> visit("/root/ruby")
    |> assert_connected()
    |> assert_has("td[data-label=Key]", text: "Ends in -key")
    |> evaluate(
      """
      (() => {
        const row = document.querySelector("#providers tbody tr");
        const cells = row.querySelectorAll("td");
        return cells[1].getBoundingClientRect().top >= cells[0].getBoundingClientRect().bottom;
      })()
      """,
      fn stacked -> assert stacked, "the cells of a provider are side by side" end
    )
  end

  @tag browser_context_opts: @phone
  test "the site menu opens from the bar, marks the part of the page, and closes",
       %{conn: session, home: home} do
    session
    |> sign_in_with_link(@address)
    |> visit("#{home}/residents")
    |> assert_connected()
    # The bar is one line: the name of the site and the button.
    |> evaluate("document.querySelector('header').getBoundingClientRect().height", fn height ->
      assert height <= 60, "the site bar is #{height}px high on a phone"
    end)
    |> refute_menu_open()
    |> click_button("Menu")
    |> assert_menu_open()
    |> assert_has("#site-menu a[aria-current]", text: "Residents", exact: true)
    |> assert_has("#site-menu span", text: @address)
    # Each link of the open menu is in the screen, and as high as a finger.
    |> evaluate(
      """
      Array.from(document.querySelectorAll("#site-menu a")).filter((link) => {
        const box = link.getBoundingClientRect();
        return box.height < 43.5 || box.left < 0 || box.right > window.innerWidth;
      }).map((link) => link.innerText)
      """,
      fn links -> assert links == [], "links of the menu that a finger misses" end
    )
    |> press("body", "Escape")
    |> refute_menu_open()
    # The bar stays at the top of the screen when the page scrolls.
    |> evaluate(
      """
      (async () => {
        document.querySelector("main").style.minHeight = "3000px";
        window.scrollTo(0, 1500);
        await new Promise((done) => requestAnimationFrame(done));
        return document.querySelector("header").getBoundingClientRect().top;
      })()
      """,
      fn top -> assert top == 0, "the site bar scrolled away" end
    )
    # A link of the menu goes to its page.
    |> click_button("Menu")
    |> click_link("#site-menu a", "Tasks")
    |> assert_has("h1", text: "Tasks", exact: true)
    |> assert_connected()
    # The menu of the new page is closed, and marks the new part.
    |> refute_menu_open()
    |> evaluate(
      "document.querySelector('#site-menu a[aria-current]').innerText.trim()",
      fn part ->
        assert part == "Tasks"
      end
    )
  end

  @tag browser_context_opts: @phone
  test "a table is a list of cards on a phone", %{conn: session, home: home} do
    session
    |> sign_in_with_link(@address)
    |> visit("#{home}/tasks")
    |> assert_connected()
    |> assert_has("tbody th[scope=row]", text: "Give Sir Reginald his evening medication")
    |> evaluate(
      """
      (() => {
        const row = document.querySelector("tbody tr");
        const done = Array.from(row.querySelectorAll("button"))
          .find((button) => button.innerText.trim() === "Done").getBoundingClientRect();
        const label = getComputedStyle(row.querySelector("td[data-label=Who]"), "::before");
        return {
          // The button of the last column is in the screen.
          in_view: done.left >= 0 && done.right <= window.innerWidth,
          // Each cell is a line of the card, below the cell before it.
          stacked: row.querySelector("th").getBoundingClientRect().top >=
            row.querySelector("td").getBoundingClientRect().bottom,
          // The header row is not in view, and is still in the page.
          header: document.querySelector("thead").getBoundingClientRect().height,
          label: label.content
        };
      })()
      """,
      fn card ->
        assert card["in_view"], "the button Done is outside the screen"
        assert card["stacked"], "the cells of a task are side by side"
        assert card["header"] <= 1
        assert card["label"] =~ "Who"
      end
    )
    # The sort of a table of Cinder is in its header, so that header stays.
    |> visit("#{home}/residents")
    |> assert_connected()
    |> assert_has("[data-key=th_class] [phx-click]", text: "Name")
    |> evaluate(
      "document.querySelector('[data-key=th_class] [phx-click]').getBoundingClientRect().height",
      fn height -> assert height >= 43.5, "the sort control is #{height}px high" end
    )
  end

  @tag browser_context_opts: [viewport: %{width: 1280, height: 800}]
  test "on a wide screen the menu is in the page, in two rows",
       %{conn: session, home: home} do
    session
    |> sign_in_with_link(@address)
    |> visit("#{home}/tasks")
    |> assert_connected()
    |> assert_has("#site-menu a[aria-current]", text: "Tasks", exact: true)
    |> evaluate(
      """
      (() => {
        const box = (selector) => document.querySelector(selector).getBoundingClientRect();
        const root = document.documentElement;
        return {
          button: box("button[popovertarget]").width,
          account: box("#site-menu ul:last-child").bottom,
          parts: box("#site-menu ul:first-child").top,
          bar: box("header").height,
          wider: root.scrollWidth - root.clientWidth
        };
      })()
      """,
      fn menu ->
        assert menu["button"] == 0, "the button Menu shows on a wide screen"
        assert menu["account"] <= menu["parts"], "the account is not above the parts"
        assert menu["bar"] <= 120, "the site bar is #{menu["bar"]}px high: a row wrapped"
        assert menu["wider"] == 0
      end
    )
  end

  defp assert_menu_open(session), do: menu_open(session, true)
  defp refute_menu_open(session), do: menu_open(session, false)

  defp menu_open(session, open?) do
    evaluate(session, "document.querySelector('#site-menu').matches(':popover-open')", fn open ->
      assert open == open?, "the site menu is #{if open, do: "open", else: "closed"}"
    end)
  end

  # What a page breaks of the rules of a phone, in words, with each closed
  # part of the page open. An empty list is a page that keeps the rules.
  defp problems do
    """
    (() => {
      document.querySelectorAll("details").forEach((details) => { details.open = true; });

      const problems = [];
      const root = document.documentElement;
      const say = (element) => {
        const words = (element.innerText || element.value || "").trim().slice(0, 30);
        return `${element.tagName.toLowerCase()}${element.id ? "#" + element.id : ""} "${words}"`;
      };
      const pressed = "button, a[data-variant], summary, select, textarea, " +
        "input:not([type=hidden], [type=checkbox], [type=radio], [type=file]), " +
        "label:has(> input[type=checkbox], > input[type=radio])";
      const typed = "select, textarea, input:not([type=hidden], [type=checkbox], [type=radio])";

      if (root.scrollWidth > root.clientWidth) {
        problems.push(`the page is ${root.scrollWidth}px wide`);
      }

      // What is inside a box that hides its overflow does not make the page wider.
      const hidden = (element) => {
        for (let box = element.parentElement; box; box = box.parentElement) {
          if (getComputedStyle(box).overflowX !== "visible") return true;
        }
        return false;
      };

      for (const element of document.querySelectorAll("body *")) {
        const box = element.getBoundingClientRect();
        if (box.width === 0 || box.height === 0) continue;

        const style = getComputedStyle(element);

        if (box.right > root.clientWidth + 1 && style.position !== "fixed" && !hidden(element)) {
          problems.push(`${say(element)} ends at ${Math.round(box.right)}px`);
        }

        if (["auto", "scroll"].includes(style.overflowX) &&
            element.scrollWidth > element.clientWidth + 1) {
          problems.push(`${say(element)} scrolls sideways`);
        }

        if (element.matches(pressed) && box.height < 43.5) {
          problems.push(`${say(element)} is ${Math.round(box.height)}px high`);
        }

        if (element.matches(typed) && parseFloat(style.fontSize) < 16) {
          problems.push(`the text of ${say(element)} is ${style.fontSize}`);
        }
      }

      return problems;
    })()
    """
  end
end
