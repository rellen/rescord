defmodule RescordWeb.Features.AccessibilityTest do
  @moduledoc """
  Holds each kind of page to the rules of accessibility, in a real browser
  (ADR 0090).

  A page test reads the markup that the server writes. It does not see the
  colours that the stylesheet gives, the names that the browser computes,
  what a script adds, or where the focus of the keyboard is. This test asks
  the browser, on the screen of a phone and on a wide screen, in the light
  and in the dark scheme:

    * no page breaks a rule of axe-core for WCAG 2.0, 2.1 and 2.2 at the
      levels A and AA, or one of its best practices;
    * each page has one `main`, one site header, one site footer, a skip
      link as the first stop of the Tab key, one `h1`, headings in order, a
      language, and a title of its own that ends with the name of the site;
    * a form with its errors, the open menu, the open filter of a list and
      a notice keep the rules;
    * with the text spacing of WCAG 1.4.12, no page is wider than a small
      phone;
    * the focus stays in the row of a button that a press replaces, goes
      to the heading of the list when the row leaves it, and goes to the
      heading of a new live page;
    * the menu of a phone closes when the Tab key leaves it.

  axe-core finds only a part of the problems of a page. A new kind of
  control still needs a person who uses it with the keyboard.

  `RescordWeb.PagesFixtures` makes the refuge and names its pages. Add a new
  page there. The test creates an organisation, so it does not run beside
  others (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.FeatureCase, async: false

  @moduletag :tmp_dir

  # The pages that a person with no session reads. The last one is the page
  # of an error.
  @open ~w(/ /sign-in /sign-in/sent /colophon /no-such-page)

  @phone %{width: 360, height: 780}
  @small %{width: 320, height: 640}
  @wide %{width: 1280, height: 800}

  setup %{tmp_dir: tmp_dir} do
    refuge =
      RescordWeb.PagesFixtures.refuge!(
        tmp_dir,
        "the.first.administrator@wattle-creek.example.org"
      )

    flush_emails()
    {:ok, refuge}
  end

  for {name, viewport, scheme} <- [
        {"a phone in the light scheme", @phone, :light},
        {"a small phone in the dark scheme", @small, :dark},
        {"a wide screen in the light scheme", @wide, :light},
        {"a wide screen in the dark scheme", @wide, :dark}
      ] do
    @tag browser_context_opts: [
           viewport: viewport,
           color_scheme: scheme,
           has_touch: viewport.width < 1000
         ]
    @tag timeout: 300_000
    test "each page keeps the rules on #{name}", %{conn: session, pages: pages} = context do
      open = Enum.flat_map(@open, &problems(visit(session, &1), &1 <> ", with no session"))

      session =
        sign_in_as_administrator(
          session,
          context,
          "#{unquote(scheme)}.#{unquote(viewport.width)}"
        )

      signed_in = Enum.flat_map(pages, &problems(visit(session, &1), &1))

      assert open ++ signed_in == [], Enum.join(open ++ signed_in, "\n\n")
    end
  end

  for {name, viewport, scheme} <- [
        {"a phone in the light scheme", @phone, :light},
        {"a wide screen in the dark scheme", @wide, :dark}
      ] do
    @tag browser_context_opts: [
           viewport: viewport,
           color_scheme: scheme,
           has_touch: viewport.width < 1000
         ]
    test "the pages of a root user keep the rules on #{name}", %{conn: session} do
      address = "root.#{unquote(scheme)}.#{unquote(viewport.width)}@wattle-creek.example.org"
      root = root!(address)
      Rescord.UsageFixtures.usage!(root)

      session = sign_in_with_link(session, address)

      found =
        Enum.flat_map(~w(/root /root/ruby /root/usage), &problems(visit(session, &1), &1))

      assert found == [], Enum.join(found, "\n\n")
    end
  end

  @tag browser_context_opts: [viewport: @phone, has_touch: true]
  test "a form with its errors, the open menu, an open filter and a notice keep the rules",
       %{conn: session, home: home} = context do
    session = sign_in_as_administrator(session, context, "states")

    errors =
      session
      |> visit("#{home}/tools/dose")
      |> assert_connected()
      |> fill_in("Weight", with: "1,095")
      |> fill_in("Dose", with: "0.2", exact: true)
      |> click_button("Calculate")
      |> assert_has("#dose_weight[aria-invalid=true]")
      |> problems("a form with its errors")

    menu =
      session
      |> visit("#{home}/residents")
      |> assert_connected()
      |> click_button("Menu")
      |> problems("the open menu")

    # The choices of a filter of Cinder (ADR 0087).
    filter =
      session
      |> visit("#{home}/residents")
      |> assert_connected()
      |> click("#residents-filter-sex-button")
      |> assert_has("#residents-filter-sex-button[aria-expanded=true]")
      |> problems("the open filter")

    notice =
      session
      |> visit("#{home}/settings")
      |> assert_connected()
      |> click_button("Save the days ahead")
      |> assert_has("#flash-info")
      |> problems("a notice")

    found = errors ++ menu ++ filter ++ notice
    assert found == [], Enum.join(found, "\n\n")
  end

  @tag browser_context_opts: [viewport: @small]
  @tag timeout: 300_000
  test "with the text spacing of WCAG 1.4.12, no page is wider than a small phone",
       %{conn: session, pages: pages} = context do
    session = sign_in_as_administrator(session, context, "spacing")

    wide =
      for page <- pages, reduce: [] do
        wide ->
          session
          |> visit(page)
          |> assert_has("h1")
          |> evaluate(spaced(), fn
            0 -> :ok
            more -> send(self(), {:wide, "#{page} is #{more}px wider than the screen"})
          end)

          receive do
            {:wide, words} -> [words | wide]
          after
            0 -> wide
          end
      end

    assert wide == [], Enum.join(Enum.reverse(wide), "\n")
  end

  @tag browser_context_opts: [viewport: @phone]
  test "the focus stays in the row of a button that a press replaces",
       %{conn: session, home: home} = context do
    session
    |> sign_in_as_administrator(context, "focus.row")
    |> visit("#{home}/tasks")
    |> assert_connected()
    |> evaluate("""
    Array.from(document.querySelectorAll("tbody button"))
      .find((button) => button.innerText.trim() === "Done").focus()
    """)
    |> press("tbody button:focus", "Enter")
    |> assert_has("tbody button:focus", text: "Open again")
  end

  @tag browser_context_opts: [viewport: @phone]
  @long_hutch "The companions of the long hutch · Rescord"

  test "the focus goes to the heading of a new live page",
       %{conn: session, home: home} = context do
    session
    |> sign_in_as_administrator(context, "focus.page")
    |> visit("#{home}/groups")
    |> assert_connected()
    |> evaluate(~s|document.querySelector("main a[data-phx-link=redirect]").focus()|)
    |> press("main a:focus", "Enter")
    |> assert_has("h1", text: "The companions of the long hutch")
    |> assert_has("h1:focus")
    |> evaluate(title_after_navigation(@long_hutch), fn title ->
      assert title == @long_hutch
    end)
  end

  # A task of an earlier day that is still open is in the list of today,
  # and leaves it when it is done. LiveView then puts the next task in its
  # row, so a second press would act on that task (ADR 0110).
  @tag browser_context_opts: [viewport: @phone]
  test "the focus goes to the heading of the list when the row of its button leaves it",
       %{conn: session, home: home, organisation: organisation, root: root} = context do
    yesterday = organisation |> Rescord.Accounts.today() |> Date.add(-1) |> Date.to_iso8601()
    {:ok, due_at} = Rescord.Accounts.local_instant(organisation, "#{yesterday}T09:00")

    Rescord.Tasks.plan_task!(%{title: "Clean the water bottles", due_at: due_at},
      actor: root,
      tenant: organisation
    )

    session
    |> sign_in_as_administrator(context, "focus.gone")
    |> visit("#{home}/tasks")
    |> assert_connected()
    |> evaluate("""
    document.querySelector("button[aria-label='Mark the task Clean the water bottles as done']").focus()
    """)
    |> press("tbody button:focus", "Enter")
    |> assert_has("#day-heading:focus")
    |> refute_has("tbody button:focus")
  end

  @tag browser_context_opts: [viewport: @phone]
  test "the menu of a phone closes when the Tab key leaves it",
       %{conn: session, home: home} = context do
    session
    |> sign_in_as_administrator(context, "focus.menu")
    |> visit(home)
    |> assert_connected()
    |> evaluate(~s|document.querySelector("[popovertarget=site-menu]").focus()|)
    |> press("[popovertarget=site-menu]", "Enter")
    |> evaluate(~s|document.getElementById("site-menu").matches(":popover-open")|, fn open ->
      assert open
    end)
    |> evaluate("""
    Array.from(document.querySelectorAll("#site-menu :is(a[href], button)")).at(-1).focus()
    """)
    |> press("#site-menu :focus", "Tab")
    |> evaluate(~s|document.getElementById("site-menu").matches(":popover-open")|, fn open ->
      refute open
    end)
  end

  # LiveView can put the title of a new live page after its h1, so a read
  # of the title right after the h1 can find the title of the page before.
  # The script waits up to 5 seconds for the title, and gives the title
  # that the page has then.
  defp title_after_navigation(title) do
    """
    (async () => {
      for (let i = 0; document.title !== #{Jason.encode!(title)} && i < 100; i++) {
        await new Promise((done) => setTimeout(done, 50));
      }
      return document.title;
    })()
    """
  end

  # An address gets few sign-in links in a while (ADR 0020), so each test
  # signs in as an administrator of its own.
  defp sign_in_as_administrator(session, %{organisation: organisation, root: root}, name) do
    address = "#{name}@wattle-creek.example.org"
    member!(organisation, :administrator, root, address)
    flush_emails()
    sign_in_with_link(session, address)
  end

  # What the page that the session shows breaks, each in words that start
  # with the name of the page. An empty list is a page that keeps the rules.
  defp problems(session, name) do
    session = evaluate(session, A11yAudit.JS.axe_core() <> "; true")

    evaluate(session, audit(), fn result -> send(self(), {:audit, result}) end)

    receive do
      {:audit, %{"axe" => axe, "own" => own}} ->
        rules =
          try do
            axe |> A11yAudit.Results.from_json() |> A11yAudit.Assertions.assert_no_violations()
            []
          rescue
            error in ExUnit.AssertionError -> [error.message]
          end

        Enum.map(rules ++ own, &"#{name}: #{&1}")
    after
      0 -> raise "the browser gave no result for #{name}"
    end
  end

  # Waits for the socket of a live page, opens each closed part, runs
  # axe-core, and then our own checks of what axe-core does not ask.
  defp audit do
    """
    (async () => {
      const live = document.querySelector("[data-phx-main]");
      for (let i = 0; live && !live.classList.contains("phx-connected") && i < 100; i++) {
        await new Promise((done) => setTimeout(done, 50));
      }

      document.querySelectorAll("details").forEach((details) => { details.open = true; });
      await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));

      const axeResult = await axe.run(document, {
        runOnly: {
          type: "tag",
          values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"]
        },
        resultTypes: ["violations"]
      });

      const own = [];
      const count = (what, list, wanted) => {
        if (list.length !== wanted) own.push(`the page has ${list.length} ${what}, and not ${wanted}`);
      };
      const shown = (element) => element.getClientRects().length > 0;
      // A header or a footer of the page, and not of a part of it.
      const ofPage = (selector) => Array.from(document.querySelectorAll(selector))
        .filter((element) => !element.parentElement.closest("article, aside, main, nav, section"));

      count("main", Array.from(document.querySelectorAll("main")), 1);
      count("site header", ofPage("header"), 1);
      count("site footer", ofPage("footer"), 1);

      const first = document.querySelector("a[href], button, input, select, textarea, summary");
      if (!first || first.getAttribute("href") !== "#main" || !document.getElementById("main")) {
        own.push("the first stop of the Tab key is not a link to main");
      }

      const headings = Array.from(document.querySelectorAll("h1, h2, h3, h4, h5, h6"))
        .filter(shown).map((heading) => Number(heading.tagName[1]));
      count("h1", headings.filter((level) => level === 1), 1);
      headings.forEach((level, index) => {
        if (index > 0 && level > headings[index - 1] + 1) {
          own.push(`a heading of level ${level} follows one of level ${headings[index - 1]}`);
        }
      });

      const navs = Array.from(document.querySelectorAll("nav"));
      const names = navs.map((nav) => nav.getAttribute("aria-label") ||
        document.getElementById(nav.getAttribute("aria-labelledby"))?.innerText);
      if (names.some((name) => !name) || new Set(names).size !== names.length) {
        own.push(`the nav elements do not each have a name of their own: ${names.join(", ")}`);
      }

      if (!document.documentElement.lang) own.push("the document has no language");

      const title = document.title;
      if (!title.endsWith(" · Rescord") || title === "Rescord · Rescord") {
        own.push(`the title "${title}" is not a title of the page and the name of the site`);
      }

      return { axe: axeResult, own };
    })()
    """
  end

  # How many pixels the page is wider than the screen, with the text
  # spacing that WCAG 1.4.12 names and each closed part open.
  defp spaced do
    """
    (async () => {
      const style = document.createElement("style");
      style.textContent = `* { line-height: 1.5 !important; letter-spacing: 0.12em !important;
        word-spacing: 0.16em !important; } p { margin-block-end: 2em !important; }`;
      document.head.append(style);

      const live = document.querySelector("[data-phx-main]");
      for (let i = 0; live && !live.classList.contains("phx-connected") && i < 100; i++) {
        await new Promise((done) => setTimeout(done, 50));
      }

      document.querySelectorAll("details").forEach((details) => { details.open = true; });
      await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));

      const root = document.documentElement;
      return Math.max(0, root.scrollWidth - root.clientWidth);
    })()
    """
  end
end
