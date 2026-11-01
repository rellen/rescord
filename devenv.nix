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
  packages =
    [
      pkgs.git
      # Phoenix asset tooling from nixpkgs. The binaries that the esbuild and
      # tailwind hex packages download are dynamically linked and won't run on
      # NixOS, so point the app's config at these instead (see MIX_*_PATH).
      pkgs.esbuild
      pkgs.tailwindcss_4
    ]
    # Phoenix live reload: file_system's Linux backend uses inotifywait.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.inotify-tools ];

  # https://devenv.sh/basics/
  env = {
    # Keep hex, rebar and mix archives inside the project, not in ~/.mix.
    MIX_HOME = "${config.devenv.state}/mix";
    HEX_HOME = "${config.devenv.state}/hex";
    ERL_AFLAGS = "-kernel shell_history enabled";

    # Read in config/config.exs:
    #   config :esbuild, path: System.get_env("MIX_ESBUILD_PATH")
    #   config :tailwind, path: System.get_env("MIX_TAILWIND_PATH")
    MIX_ESBUILD_PATH = lib.getExe pkgs.esbuild;
    MIX_TAILWIND_PATH = lib.getExe pkgs.tailwindcss_4;
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

  enterShell = ''
    mix local.hex --force --if-missing >/dev/null
    mix local.rebar --force --if-missing >/dev/null
  '';

  # https://devenv.sh/tests/
  enterTest = ''
    elixir --version | grep --color=auto "Elixir ${elixir.version}"
    wait_for_port 5432
    psql -U postgres -h 127.0.0.1 -d postgres -c 'select version()' | grep --color=auto "PostgreSQL 18"
  '';
}
