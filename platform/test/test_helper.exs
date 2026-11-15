# The browser tests (tagged :playwright, ADR 0023) need the driver of
# Playwright and a browser. A machine without the driver runs every other
# test, and says that it left the browser tests out.
assets_dir = Application.fetch_env!(:phoenix_test, :playwright)[:assets_dir]
driver = Path.join([assets_dir, "node_modules", "playwright", "package.json"])

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

ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Rescord.Repo, :manual)
