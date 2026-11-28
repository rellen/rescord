{
  pkgs,
  lib,
  config,
  ...
}:

let
  # Elixir 1.20.x on Erlang/OTP 29 (Elixir 1.20 supports OTP 27–29).
  # The exact patch version (1.20.5) is pinned by devenv.lock.
  beam = pkgs.beam.packages.erlang_29;
  elixir = beam.elixir_1_20;

  # The browser tests drive a real Chromium through Playwright (ADR 0023).
  # phoenix_test_playwright looks for the driver in
  # <assets dir>/node_modules/playwright. This directory gives it the driver
  # of nixpkgs, so the project needs no npm package.
  playwrightAssets = pkgs.runCommand "playwright-assets" { } ''
    mkdir -p $out/node_modules
    ln -s ${pkgs.playwright-driver} $out/node_modules/playwright
  '';

  # The browser is from the same nixpkgs as the driver, so the two are one
  # version. A test runs with no window, and Playwright uses the headless
  # shell of Chromium for that. To see the browser (`headless: false`), set
  # `withChromium = true` here.
  playwrightBrowsers = pkgs.playwright-driver.selectBrowsers {
    withChromium = false;
    withFirefox = false;
    withWebkit = false;
    withFfmpeg = false;
  };
in
{
  # https://devenv.sh/languages/
  languages.elixir = {
    enable = true;
    package = elixir;
    # Build the language server against the same Elixir/OTP as the project.
    lsp.package = beam.elixir-ls.override { inherit elixir; };
  };

  # https://devenv.sh/packages/
  packages = [
    pkgs.git
    # The scan for secrets of scripts/check-secrets.sh (ADR 0064).
    pkgs.gitleaks
    # esbuild bundles the JS and the classless CSS. The binary that the
    # esbuild Hex package downloads won't run on NixOS, so the app's config
    # points at this one instead (MIX_ESBUILD_PATH).
    pkgs.esbuild
    # The photos (ADR 0055): vix links against the libvips of nixpkgs, and
    # finds it with pkg-config (VIX_COMPILATION_MODE below).
    pkgs.vips
    pkgs.pkg-config
  ]
  # Phoenix live reload: file_system's Linux backend uses inotifywait.
  ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.inotify-tools ];

  # https://devenv.sh/basics/
  env = {
    # Keep hex, rebar and mix archives inside the project, not in ~/.mix.
    MIX_HOME = "${config.devenv.state}/mix";
    HEX_HOME = "${config.devenv.state}/hex";
    ERL_AFLAGS = "-kernel shell_history enabled";

    # Used as the esbuild `path` in platform/config/config.exs.
    MIX_ESBUILD_PATH = lib.getExe pkgs.esbuild;

    # vix builds its NIF against pkgs.vips, and never downloads a libvips
    # that would not run on NixOS (ADR 0055).
    VIX_COMPILATION_MODE = "PLATFORM_PROVIDED_LIBVIPS";

    # Read by platform/config/test.exs and by Playwright (ADR 0023).
    PLAYWRIGHT_ASSETS_DIR = "${playwrightAssets}";
    PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };

  # https://devenv.sh/services/
  services.postgres = {
    enable = true;
    package = pkgs.postgresql_18;
    # Listen on TCP as well as the unix socket, as Phoenix's default
    # `hostname: "localhost"` expects.
    listen_addresses = "127.0.0.1";
    # Matches the credentials in Phoenix's generated config/dev.exs and
    # config/test.exs. Local connections use trust auth, so the password
    # is never checked.
    initialScript = ''
      CREATE ROLE postgres WITH LOGIN SUPERUSER PASSWORD 'postgres';
    '';
  };

  # The store of the attachments on this machine (ADR 0038): Garage 2, with
  # the bucket `rescord` and a fixed key for development, which
  # `platform/config/runtime.exs` names. The key opens this store alone.
  services.garage = {
    enable = true;
    package = pkgs.garage_2;
    region = "garage";
    buckets = [ "rescord" ];
    afterStart = ''
      if ! $GARAGE key info rescord-dev >/dev/null 2>&1; then
        $GARAGE key import --yes -n rescord-dev \
          GK0000000000000000000000ad \
          000000000000000000000000000000000000000000000000000000000000dec0
      fi
      $GARAGE bucket allow --read --write --owner rescord --key rescord-dev
    '';
  };

  # The last lines install two hooks of Git. The hook commit-msg checks that
  # the message of a commit follows Conventional Commits (ADR 0060). The hook
  # pre-commit scans what the commit holds for secrets (ADR 0064). A hook
  # that is there stays.
  enterShell = ''
    mix local.hex --force --if-missing >/dev/null
    mix local.rebar --force --if-missing >/dev/null

    if hooks=$(git rev-parse --git-path hooks 2>/dev/null); then
      mkdir -p "$hooks"

      if [ ! -e "$hooks/commit-msg" ] && [ ! -L "$hooks/commit-msg" ]; then
        ln -s "$DEVENV_ROOT/scripts/check-commit-message.sh" "$hooks/commit-msg"
      fi

      if [ ! -e "$hooks/pre-commit" ] && [ ! -L "$hooks/pre-commit" ]; then
        ln -s "$DEVENV_ROOT/scripts/check-secrets.sh" "$hooks/pre-commit"
      fi
    fi
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    elixir --version | grep --color=auto "Elixir ${elixir.version}"
    wait_for_port 5432
    psql -U postgres -h 127.0.0.1 -d postgres -c 'select version()' | grep --color=auto "PostgreSQL 18"
    test -x "$PLAYWRIGHT_ASSETS_DIR/node_modules/playwright/cli.js"
    gitleaks version
  '';
}
