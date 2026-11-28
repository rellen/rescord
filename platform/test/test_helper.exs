# The browser tests (tagged :playwright, ADR 0023) need the driver of
# Playwright and a browser. A machine without the driver runs every other
# test, and says that it left the browser tests out.
assets_dir = Application.fetch_env!(:phoenix_test, :playwright)[:assets_dir]
driver = Path.join([assets_dir, "node_modules", "playwright", "package.json"])

# In CI a missing driver is a fault of the set-up: a run that left the
# browser tests out would pass and test less.
if System.get_env("CI") == "true" and not File.exists?(driver) do
  raise "CI has no Playwright driver at #{driver}: run the tests inside the devenv shell"
end

exclude =
  if File.exists?(driver) do
    {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
    Application.put_env(:phoenix_test, :base_url, RescordWeb.Endpoint.url())
    []
  else
    IO.puts(:stderr, """

    The browser tests (tagged :playwright) are EXCLUDED: no Playwright driver at
    #{driver}.
    Run the tests inside the devenv shell, or set PLAYWRIGHT_ASSETS_DIR.
    """)

    [:playwright]
  end

# render_async/1 and assert_receive/2 wait for assert_receive_timeout, 100 ms
# by default. CI runs 4 parts of the tests at once on a runner of 4 cores
# (ADR 0103), and there an async load or a task of a page took longer than
# that. A longer wait costs nothing when the message comes, only when a test
# fails. refute_receive keeps its own short wait.
ExUnit.start(exclude: exclude, assert_receive_timeout: 2_000)
Ecto.Adapters.SQL.Sandbox.mode(Rescord.Repo, :manual)
