# rescord

The Phoenix + Ash application (`:rescord`) lives in [`platform/`](platform/).

## Development

The dev environment is defined with [devenv](https://devenv.sh) (2.x):
Elixir 1.20.5 on Erlang/OTP 29 and PostgreSQL 18, pinned by `devenv.lock`.

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
