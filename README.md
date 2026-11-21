# rescord

A management system for an animal rescue or an animal refuge. See
[`docs/domain.md`](docs/domain.md) for the domain.

The Phoenix + Ash application (`:rescord`) lives in [`platform/`](platform/).

## Development

The dev environment is defined with [devenv](https://devenv.sh) (2.x):
Elixir 1.20.5 on Erlang/OTP 29, PostgreSQL 18, and the Playwright driver with
Chromium for the browser tests, pinned by `devenv.lock`.

```bash
devenv up -d   # start PostgreSQL 18 in the background (127.0.0.1:5432, role postgres/postgres)
devenv shell   # enter the environment
devenv test    # check Elixir and PostgreSQL versions
```

Then, inside the shell:

```bash
cd platform
mix setup                 # deps, database (ash.setup), assets
iex -S mix phx.server     # http://localhost:4000
```

## Self-hosting

A rescue runs Rescord on a server of its own: with Docker Compose, on
NixOS, or from a tarball with systemd. [`docs/self-hosting.md`](docs/self-hosting.md)
says what the server needs, how to install, each setting, and how to back
up and upgrade.

Conventions are in [`AGENTS.md`](AGENTS.md), the design in
[`docs/architecture.md`](docs/architecture.md), and each decision in
[`docs/adr/`](docs/adr/).

## Licence

Rescord is under the MIT licence: see [`LICENSE`](LICENSE). The typeface
Atkinson Hyperlegible, in `platform/priv/static/fonts/`, keeps its own
licence, which is next to it.
