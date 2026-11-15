# ADR 0023: Browser tests with PhoenixTest.Playwright

Status: accepted

## Context

The maintainer asked for a test that signs a person in from end to end, with
`phoenix_test_playwright` (15 November 2026). The tests of ADR 0018 to 0022
send requests and drive a LiveView in the test process. They do not show
what only a browser shows: that a person finds each control by its words,
that the script of the page works, and that the session of the sign-in
reaches the socket of a LiveView.

`phoenix_test_playwright` 0.19 drives a browser through the Node driver of
Playwright. It looks for the driver in `<assets dir>/node_modules/playwright`.
`playwright_ex` 0.16, below it, needs Playwright 1.64 or later. The project
has no npm package and no `package.json` (ADR 0002).

## Decision

- **A browser test uses `RescordWeb.FeatureCase`**, which uses
  `PhoenixTest.Playwright.Case`. Its tests have the tags `:playwright` and
  `:postgres`, and are in `platform/test/rescord_web/features/`.
- **devenv supplies the driver and the browser, from nixpkgs.**
  `devenv.nix` builds a directory whose `node_modules/playwright` is the
  `playwright-driver` of the pinned nixpkgs, and names it in
  `PLAYWRIGHT_ASSETS_DIR`. `PLAYWRIGHT_BROWSERS_PATH` names the headless
  shell of Chromium of the same nixpkgs. The driver and the browser are thus
  one version, and the project still has no npm package.
- **A machine with no driver runs each other test.** `test/test_helper.exs`
  looks for the driver. When it is not there, the helper leaves the tests
  with the tag `:playwright` out, and says so on the standard error.
- `PLAYWRIGHT_CHROMIUM` names another Chromium, for a machine that has the
  driver and a browser from another place.
- **The tests run a server**, on port 4002. `config/runtime.exs` sets the
  port only outside the tests. Before this record it set the port for each
  environment, which the tests did not see, because they ran no server.
  `RescordWeb.EndpointPortTest` holds the port.
- **The tests build the assets first.** The alias `test` runs `assets.build`,
  because a browser loads `app.js` and `app.css` from `priv/static`, which
  git does not hold. A stale file there would give a wrong result with no
  error.
- **The database.** `PhoenixTest.Playwright.Case` starts the sandbox and puts
  its owner in the `User-Agent` of the browser. In the tests only, the
  endpoint has the plug `Phoenix.Ecto.SQL.Sandbox`, the socket of a LiveView
  reads the `User-Agent`, and `RescordWeb.LiveSandbox` is the first hook of
  each live session. A request and a LiveView of a browser test thus use the
  transaction of that test.
- **The email.** The email of a sign-in link leaves from a task (ADR 0019),
  which is not the test process and has no `User-Agent`. So a browser test
  that reads an email is `async: false`: the sandbox is then shared, and
  `RescordWeb.FeatureCase` names the test process as the one that gets each
  email of the Swoosh test adapter.

## Consequences

- `mix test` listens on port 4002. Two runs at one time cannot both have it.
- `mix test` builds the assets each time, which takes less than a second.
- Outside the devenv shell, `mix test` leaves the browser tests out. Read
  the first lines of its output: a run that left them out says so.
- The first browser test is `RescordWeb.Features.SignInTest`. These changes
  each made it fail: a page with no script for the sign-out link, a socket
  that does not get the session, a link that works two times, and a field
  with no label.
- A browser test with `async: true` needs more: an email that reaches the
  right test, and a sandbox for a task that has no `User-Agent`. No test
  needs that today.
- The browser tests do not check the page for accessibility faults. That
  needs axe, which is a script from npm, and a decision of the maintainer.
