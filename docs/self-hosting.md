# Run Rescord on a server of your own

A rescue, or a group of rescues, runs Rescord on a server of its own
(ADR 0044). This guide tells you what the server needs, the three ways to
install Rescord, each setting, and how to back up and upgrade.

## What you need

- A Linux server with 2 GB of memory or more, on x86-64 or ARM64.
- PostgreSQL 18 or later. The Docker Compose file and the NixOS module make
  the database for you.
- A name for the server, such as `rescord.example.org`, and HTTPS in front
  of Rescord. Rescord sends each request without HTTPS to HTTPS. The
  Compose file uses Caddy for HTTPS, and the NixOS module can use nginx.
- An SMTP server that may send mail for your address. Rescord sends the
  sign-in links and the invitations through it. Postmark, Amazon SES,
  Mailgun, Fastmail and the mail host of your domain all give one.
- A place for the photos of the residents and the files of the journal: a
  directory of the server, or a bucket of a service that is compatible
  with S3.

## The releases

Each version of Rescord has a tag such as `v0.2.0`, a section in
`CHANGELOG.md`, the image `ghcr.io/rellen/rescord` with the tag of the
version, and a GitHub release with the tarballs. Install the newest one:
<https://github.com/rellen/rescord/releases/latest>. This guide names
`v0.2.0`.

The number of a version says what an upgrade needs (ADR 0060). A new patch
or a new minor needs a backup, the new version and a start. A new major
needs a step by hand, and before 1.0.0 a new minor can need one too. The
section "Upgrade notes" of the release in `CHANGELOG.md` says which.

The branch `main` has changes that no release has yet. Read this guide at
the tag of the version that you install.

## Install

### With Docker Compose

`deploy/compose` holds the Compose file, a Caddyfile and `env.example`.

1. Take the files of the release on the server:

   ```sh
   git clone --branch v0.2.0 https://github.com/rellen/rescord.git
   cd rescord/deploy/compose
   ```

2. Copy `env.example` to `.env`, and fill it in. Make each secret with
   `openssl rand -base64 48`. `RESCORD_IMAGE` names the image of the
   release, `ghcr.io/rellen/rescord:0.2.0`. To build the image yourself,
   run `docker build -t rescord:local platform` in the repository, and set
   `RESCORD_IMAGE=rescord:local`.
3. Point the name of the server at it, and open the ports 80 and 443.
4. Start Rescord:

   ```sh
   docker compose up -d
   ```

5. Check the server, with your own address for a test email (see "Check
   the server" below):

   ```sh
   docker compose exec rescord bin/check you@example.org
   ```

6. Make the first root user, and ask for a sign-in link on the sign-in page:

   ```sh
   docker compose exec rescord bin/bootstrap-root you@example.org
   ```

The volume `db` holds the database, and the volume `files` holds the files.

### On NixOS

Add the flake of Rescord to the flake of the machine:

```nix
{
  inputs.rescord.url = "github:rellen/rescord/v0.2.0";

  outputs = { nixpkgs, rescord, ... }: {
    nixosConfigurations.refuge = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        rescord.nixosModules.default
        {
          services.rescord = {
            enable = true;
            host = "rescord.example.org";
            environmentFile = "/run/secrets/rescord.env";
            nginx.enable = true;
            settings = {
              RESCORD_SMTP_HOST = "smtp.example.org";
              RESCORD_SMTP_USERNAME = "rescord";
              RESCORD_MAIL_FROM = "rescord@example.org";
            };
          };
          security.acme = {
            acceptTerms = true;
            defaults.email = "you@example.org";
          };
        }
      ];
    };
  };
}
```

The module makes a PostgreSQL 18 database `rescord` on the machine, with a
login over the local socket and no password. It keeps the files in
`/var/lib/rescord/files`. Put the secrets in `environmentFile`, which only
root reads, and never in the configuration: the configuration is in the Nix
store, which each user of the machine reads. A tool such as sops-nix or
agenix can make that file.

The module installs `rescord-check`, which checks the server (see "Check
the server" below), and `rescord-bootstrap-root`, which makes the first
root user. It also installs `rescord-restore` (see "Restore"),
`rescord-move-storage` (see "Move the files to another store"),
`rescord-check-files` (see "Check the files"),
`rescord-rotate-vault` (see "Change the secret of the keys") and
`rescord-migrate` (see "The rehearsal of an upgrade"). Each runs
with the environment of the service. Run them as root:

```sh
rescord-check you@example.org
rescord-bootstrap-root you@example.org
```

`nix flake check` also runs a NixOS test of the module, which is slow
without KVM.

### From the tarball, with systemd

The tarball holds the release, its Erlang runtime, and the libvips that
makes the photos safe to keep (ADR 0055), so the server needs no libvips of
its own. It runs on a system
with glibc 2.36 or later and OpenSSL 3: Debian 12 and later, Ubuntu 24.04
and later, and Fedora 37 and later. Each GitHub release of Rescord has the
tarballs for amd64 and arm64, and `SHA256SUMS`. Take the tarball for the
architecture of the server, and check it before you unpack it:

```sh
sha256sum --check --ignore-missing SHA256SUMS
```

Copy `deploy/systemd` of the repository, at the tag of the release, to the
server too. `scripts/release-tarball.sh amd64` builds a tarball from the
repository, on a machine with Docker.

1. Install PostgreSQL 18, and make a database and a user:

   ```sh
   sudo -u postgres createuser --pwprompt rescord
   sudo -u postgres createdb --owner rescord rescord
   ```

2. Unpack the tarball into `/opt/rescord`, and make the user of the service:

   ```sh
   sudo mkdir -p /opt/rescord
   sudo tar -xzf rescord-linux-amd64.tar.gz -C /opt/rescord --strip-components 1
   sudo useradd --system --home /var/lib/rescord --shell /usr/sbin/nologin rescord
   ```

3. Copy `deploy/systemd/rescord.env.example` to `/etc/rescord/rescord.env`,
   give it the mode 0600, and fill it in.
4. Copy `deploy/systemd/rescord.service` to `/etc/systemd/system/`, and
   start it:

   ```sh
   sudo systemctl enable --now rescord
   ```

5. Put a reverse proxy with HTTPS in front of `localhost:4000`. It must pass
   WebSocket connections through, because the pages of Rescord use them, and
   add the address of the client to `X-Forwarded-For`. Caddy does both by
   default; nginx does with `proxy_set_header X-Forwarded-For
   $proxy_add_x_forwarded_for;` and the headers for WebSocket. A proxy on
   another machine goes in `RESCORD_TRUSTED_PROXIES`.
   The address of a calendar feed holds a secret token, as
   `/o/<short name>/calendar.ics?token=...`. Rescord keeps it out of its
   own log. A proxy that logs the whole address of each request holds
   those tokens in its log: keep that log as you keep a secret, or leave
   the query out of it.
6. Check the server (see "Check the server" below), and make the first root
   user, each with the settings of the service:

   ```sh
   rescord() {
     sudo systemd-run --quiet --pipe --wait --uid=rescord \
       --property=EnvironmentFile=/etc/rescord/rescord.env \
       --setenv=RESCORD_FILES_DIR=/var/lib/rescord/files \
       --setenv=RELEASE_DISTRIBUTION=none \
       "/opt/rescord/bin/$@"
   }
   rescord check you@example.org
   rescord bootstrap-root you@example.org
   ```

## Check the server

`bin/check` checks that the server is ready, before you go live and after
you change a setting. It prints the version of Rescord and a line for each
check, and exits with 1 when one fails:

```text
Rescord 0.2.0

ok    database   PostgreSQL 18.1
ok    migrations each migration has run
ok    store      the directory /var/lib/rescord/files takes, gives back and deletes a file
note  libvips    8.18.7 reads the photos
ok    mail       smtp.example.org:587 takes the connection with STARTTLS, and the user rescord
ok    vault      each of the 3 encrypted values opens with the secret of this server
note  assistant  no provider yet. A root user adds one at /root/ruby
ok    usage      kept on this server, and sent nowhere
ok    checks     each sanity check passes
ok    email      sent to you@example.org: look for it in that inbox, and in its spam

Rescord is ready.
```

- **database**: Rescord reaches the database of `DATABASE_URL`, which is
  PostgreSQL 18 or later.
- **migrations**: a note, and no fault, when some have not run: the next
  start runs them.
- **store**: Rescord puts a small file in the store, reads it, and deletes
  it.
- **libvips**: the version of libvips that reads the photos, a note. A
  fix of libvips or of one of its decoders reaches the Docker image and
  the tarball with a new version of Rescord with a new `vix`; the Nix
  package takes the libvips of nixpkgs. Compare this version with an
  advisory. The
  colophon shows it too, to a person who is signed in.
- **mail**: the SMTP server takes the connection, the TLS and the user of
  the settings. This check sends nothing.
- **vault**: each value that Rescord keeps encrypted opens with
  `RESCORD_KEY_SECRET`: the keys of the transfers between servers, and
  the key of each provider of the assistant. A fault here means that the
  secret is not the one that encrypted them. A note names the next step
  while the secret changes (see "Change the secret of the keys").
- **assistant**: a line for each provider of the assistant (see "The
  assistant, Ruby"): where the records go, whether it has its key, and
  what its last test found. This check reads the database. It sends no
  request to a provider, and costs nothing.
- **usage**: what the server does with its usage counts (see "Usage
  counts"): a note when they are off, and a fault when the last send
  failed. The line names no address, and the check sends nothing.
- **checks**: what the sanity checks found at their last run (see "The
  sanity checks"): a fault when a check fails, or when the newest run is
  older than 3 hours, which means that the job of the checks has stopped.
  A note on a new server, before the first run. It runs no check.
- **email**: with an address, Rescord sends a short email to it. When the
  email does not arrive, ask the provider of the SMTP server, and check
  the SPF and DKIM records of the domain of `RESCORD_MAIL_FROM`.

No line shows a password or a key.

## The sanity checks

Each hour, at minute 47, Rescord runs the sanity checks that are due
(ADR 0114): checks of its data and of the server that look for drift, a
state that nothing should leave behind. A root user reads what they found
at `/root/health`, and can run each of them now from there. Each check
runs in a transaction that PostgreSQL holds read-only, with a limit of 10
seconds for each statement, so a check changes nothing, and a slow one
stops. A check keeps a level, a count and at most 20 ids: never a name, an
address or a note.

- **Passes**: nothing found.
- **Note**: something to know, that is not a fault.
- **Fails**: somebody must act. The page says what the fault means, and
  what to do.
- **Could not run**: the check raised, or ran out of time. Three runs in
  a row that could not run are a fault.

A change of the level of a check writes one line in the log, such as
`The check jobs is fail with a count of 3`. With the metrics on (see "The
metrics"), `rescord_health_level{check="jobs"}` is 0 when a check passes,
1 for a note, 2 for a fault and 3 when it could not run: an alert of
Prometheus or Grafana can watch it. `bin/check` fails when a check fails.

The checks of the server:

| Check | How often | What a fault means |
|---|---|---|
| `vault` | each day | A value that no secret of the server opens (see "Change the secret of the keys") |
| `secrets_set` | each day | A setting says that it has a key or a token, and has none |
| `managers` | each day, for each organisation | Nobody in the organisation can manage its members |
| `root_users` | each day | The server has no root user |
| `jobs` | each hour | A job waits to start for more than 15 minutes, or runs for more than 30 |
| `cron` | each hour | An hourly job has not ended well for 2 hours |
| `migrations` | each hour | A schema has a migration that has not run, while the server runs |
| `clock` | each hour | The clocks of the server and of the database differ by more than 30 seconds (a note from 2) |

## The settings

Rescord reads each setting from the environment when it starts. A required
setting that is missing, and a setting with a value that Rescord does not
take, stop the start with the name of the setting.

| Setting | Required | Default | What it is |
| --- | --- | --- | --- |
| `DATABASE_URL` | yes | | The database, as `ecto://USER:PASSWORD@HOST/DATABASE`, or with `postgres://` or `postgresql://`. Add `?socket_dir=/run/postgresql` for a login over the local socket. Write a character of the password that a URL may not hold as a `%` code, such as `%20` for a space. Rescord stops at the start when the value is no URL with a host. |
| `PHX_HOST` | yes | | The name of the server in each link that Rescord sends, such as `rescord.example.org`. |
| `PORT` | no | `4000` | The port of the web server, behind the reverse proxy. |
| `RESCORD_LISTEN_ADDRESS` | no | `0.0.0.0` | The address that the web server listens on. `127.0.0.1` for a reverse proxy on the same machine, which the NixOS module and the systemd unit set. `::` for IPv6 and IPv4. |
| `RESCORD_TRUSTED_PROXIES` | no | `127.0.0.0/8, ::1` | The reverse proxies that say the address of each client in `X-Forwarded-For`, as addresses and networks separated by commas. Rescord counts the limits of the sign-in for each client by that address. The default trusts a proxy on the same machine; the Compose file trusts the networks of Docker. |
| `SECRET_KEY_BASE` | yes | | A secret of 64 bytes or more, which signs the sessions. |
| `TOKEN_SIGNING_SECRET` | yes | | A secret of 64 bytes or more, which signs the sign-in tokens. |
| `RESCORD_KEY_SECRET` | yes | | A secret of 32 bytes or more. It guards the private keys of the transfers between servers (ADR 0043), and each secret that Rescord keeps in its database, such as the key of a provider of the assistant (ADR 0068). Keep it with the backups. |
| `RESCORD_KEY_SECRET_PREVIOUS` | no | | The secret that `RESCORD_KEY_SECRET` had before, only while that secret changes (see "Change the secret of the keys"). |
| `RESCORD_SMTP_HOST` | yes | | The SMTP server. |
| `RESCORD_SMTP_PORT` | no | `587` | Its port: usually 587 for `starttls` and 465 for `tls`. |
| `RESCORD_SMTP_TLS` | no | `starttls` | `starttls`, `tls` (encrypted from the start), or `none` for a relay on the same machine or private network alone. With TLS, Rescord checks the certificate of the server. |
| `RESCORD_SMTP_USERNAME` | no | | The user, when the server asks for one. |
| `RESCORD_SMTP_PASSWORD` | no | | Its password. |
| `RESCORD_MAIL_FROM` | yes | | The address that the mail comes from. The SMTP server must allow it. |
| `RESCORD_MAIL_FROM_NAME` | no | `Rescord` | The name that the mail comes from, such as the name of the rescue. |
| `RESCORD_STORAGE` | no | `disk` | Where the photos and the PDFs go: `disk` or `s3`. |
| `RESCORD_FILES_DIR` | with `disk` | | The directory of the files. The user of Rescord must write it. |
| `RESCORD_S3_ENDPOINT` | with `s3` | | The address of the service, with `http://` or `https://`, such as `https://s3.example.org`. |
| `RESCORD_S3_REGION` | no | `auto` | The region that the service asks for. |
| `RESCORD_S3_BUCKET` | with `s3` | | The bucket. |
| `RESCORD_S3_ADDRESSING` | no | `path` | Where the bucket goes in each address: `path`, as in `https://s3.example.org/rescord/...`, or `virtual`, as in `https://rescord.s3.example.org/...`. Garage and MinIO take `path` as they are set up by default. Tigris needs `virtual`, with the endpoint `https://t3.storage.dev` and the region `auto`. |
| `RESCORD_S3_ACCESS_KEY_ID` | with `s3` | | The key of a user that may read and write the bucket. |
| `RESCORD_S3_SECRET_ACCESS_KEY` | with `s3` | | Its secret. |
| `RESCORD_PHOTO_SLOTS` | no | `2` | The number of photos that Rescord works on at the same time (ADR 0056). A photo of a phone takes about 150 MB while Rescord turns it and removes its metadata, and the largest photo about 300 MB. More photos wait for their turn. Give a server with more memory a larger number. |
| `RESCORD_LOG_LEVEL` | no | `info` | How much the log holds: `debug`, `info`, `warning` or `error` (see "The log"). `debug` also writes what people type, so use it for a short time. |
| `RESCORD_METRICS_PORT` | no | | A port for the metrics of the server, in the format of Prometheus (see "The metrics"). With no port, Rescord measures nothing. The metrics have no sign-in: do not publish this port. |
| `POOL_SIZE` | no | `10` | The number of connections to the database. |
| `RESCORD_BACKUP_KEEP_DAYS` | no | `14` | The number of days that a backup keeps a dump of the database (see "Back up"). |
| `ECTO_IPV6` | no | `false` | `true` to reach the database over IPv6. |

`GET /health` answers `ok` while Rescord and its database work, and the
Docker image and the Compose file use it.

The assistant has no setting here, and no other setting of this list is
for it (see "The assistant, Ruby").

## The log

Rescord writes its log to the standard output, one event on a line.
`journalctl -u rescord`, `docker compose logs rescord` or the log of your
host shows it. A line has the time, the fields that say whose it is, the
level, and the words:

```text
09:14:02.118 request_id=GHx1 user=6f0c… organisation=1b7e… [info] Sent 200 in 31ms
09:15:40.006 organisation=1b7e… job=412 worker=AshOban.Signals.Worker queue=default attempt=3 [warning] The job 412 of AshOban.Signals.Worker failed on try 3 of 16, and runs again later: Oban.PerformError(reason: {:error, binary})
```

- **The fields.** `request_id` is one request. `user` and `organisation`
  are ids, and never a name or an address: the page of a root user shows
  the organisations, and the members page of an organisation its people.
  `job`, `worker`, `queue` and `attempt` are a background job. To follow
  one person or one job, search the log for its id.
- **The levels.** `error`: Rescord lost work, or needs you. `warning`: a
  thing failed, and Rescord went on or tries again. `info`: the requests
  and the events of a normal day. `RESCORD_LOG_LEVEL` sets the lowest level
  that Rescord writes.
- **A job that fails** writes a warning each time that Rescord tries it
  again, and an error after the last try.
- **What a line does not hold.** Rescord writes no name and no address of
  a person, no text that a person typed, no token, no key, and no content
  of a file. An error is in the log as its kind, and not as its message.
  When a page stops with a fault, the line names the function and the
  line of the code, and the shape of the message that stopped it, such as
  `{:record, map(2)}`.
- **What a line can hold.** The path of a request has the short name of
  an organisation and the id of a record. The message of an unexpected
  fault of a library can name a value. So keep the log as private as the
  database, and keep it only as long as you need it.
- **`debug`** is for a fault that you cannot find. At that level the
  libraries write the parameters of each query and of each event of a
  page, which is the data of the rescue. Set it, look, and set `info`
  again.

Rescord sends its log and its errors to no other service.

## The metrics

Rescord can give numbers about itself to a collector such as Prometheus:
how long the requests, the pages, the queries and the actions take, the
jobs that fail, the emails, the replies of the assistant, and the memory.
It is off until you set
`RESCORD_METRICS_PORT`, for example to `9568`. Rescord then answers
`GET /metrics` on that port, on the address of `RESCORD_LISTEN_ADDRESS`,
in the text format of Prometheus. Each other path there answers 404.

```yaml
scrape_configs:
  - job_name: rescord
    static_configs:
      - targets: ["127.0.0.1:9568"]
```

- The port has no sign-in and no TLS. Do not put it behind the reverse
  proxy of the pages, and do not open it in a firewall. With Docker
  Compose, publish it to the machine alone
  (`127.0.0.1:9568:9568`), or let the collector join the network of the
  Compose file.
- The name of each metric starts with `rescord_`, and each time is in
  milliseconds. No label holds the id of a person or the name of an
  organisation: a label is a route, a module, a worker, or a status.
- The metrics `rescord_ruby_reply_*` count the replies of the assistant,
  by how each ended and why one failed, with the requests, the tokens and
  about what they cost, in millionths of a US dollar, for the whole
  server. The use of one organisation is in its own records, and the bill
  of the provider is the truth.
- The numbers start at zero when Rescord starts.
- `rescord_usage_count` counts the use of each feature (see "Usage
  counts").
- The numbers of a rescue (the residents, the tasks) are on its pages, and
  not here.

## Usage counts

Rescord counts how often each feature is used on the server, for each
day: the pages that open, the actions that people run, and the files
that Rescord sends, such as a report or a calendar feed (ADR 0098). A
count holds a day, a feature, a kind and the name of a page, an action
or a file as the code names it. It holds no person, no organisation, no
record, no host name and no time closer than the day.

**Nothing leaves the server unless you send it.** A new or upgraded
server counts, and shows the counts to its root users on the page
`/root/usage`. Rescord has no address of its own to send to. On that
page a root user chooses one of three modes:

- **Count on this server** (the default): the counts stay in the
  database, 400 days at most.
- **Count, and send each day**: each hour, Rescord sends each full day
  (UTC) that is not sent yet to the one address that you give, with
  `POST`. It sends no day before the day that you turned this on, none
  older than 7 days, and none with no count. It follows no redirect. A
  day that the address does not take is sent again the next hour.
- **Count nothing**: Rescord stores no new count. "Delete the counts"
  empties the table.

The format of a send is **OpenTelemetry** by default: the metrics of
OTLP as JSON over HTTP, which an OpenTelemetry Collector takes at
`/v1/metrics`. The other format is a plain JSON document of Rescord. The
page shows the exact document of the last full day before you send
anything, and "Send a test" sends a document with no count.

```yaml
# A Collector that takes the counts of Rescord.
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
exporters:
  debug: {}
service:
  pipelines:
    metrics:
      receivers: [otlp]
      exporters: [debug]
```

- A token is optional. Rescord sends it as `authorization: Bearer`, only
  to an address with `https://` or to this machine. It keeps the token
  encrypted with the secret of the server, and no page shows it again.
- The document names the server only by a random id, which comes from
  nothing of the server. "Make a new id" cuts the tie between what was
  sent before and what comes next.
- **The metrics endpoint has the counts too.** With
  `RESCORD_METRICS_PORT` (see "The metrics"), the counter
  `rescord_usage_count` with the labels `feature` and `kind` counts each
  use, in each mode but "Count nothing". A collector that reads
  Prometheus then has the counts, and you name no address. It starts at
  zero when Rescord starts; the counts of each day stay in the database.
- On a server with one person, a day of counts still says what that
  person used on that day. You can tell the rescues on your server:
  "Rescord counts which of its features are used on this server, each
  day, with no name, record or organisation in a count. The counts stay
  on the server" (and, in the mode that sends: "and go each day to …").

## Back up

Each way of installing backs Rescord up by itself, each day (ADR 0050). A
backup is a dump of the database, with the schema of each organisation,
and a copy of each new file of the store. A dump is kept for 14 days,
`RESCORD_BACKUP_KEEP_DAYS`. A bucket of S3 is not copied: keep it with the
versions of its provider.

Keep the dumps for a short time. A person who asks a rescue to erase
their data (ADR 0105) is still in each dump from before, until the dump
goes: 14 days by default. Do not keep them for more than 90 days, and
keep the copies that you make elsewhere for the same days. The privacy
notice of a rescue can then say how long its backups hold a person.

As a root user, fill in the page `/root/privacy` after the first sign-in:
who runs the server, where a person writes to you about their account,
the country and the provider of the servers and the files, the provider
of the email, and the days of `RESCORD_BACKUP_KEEP_DAYS`. The privacy
notices (`/privacy`, and the link of each rescue on its page Privacy)
say that they are not finished until you do. The same page erases an
account when a person asks you, the operator.

The backups are on the server. Copy them to another place each day too,
with the secrets: the environment file or `.env`. A backup does not hold
the secrets, and without `RESCORD_KEY_SECRET`, Rescord cannot open the keys
of the transfers between servers, and each partner must record a new
partner card. It cannot open the key of a provider of the assistant
either, and a root user must type that key again. Try a restore on
another machine one time.

- **Docker Compose**: the service `backup` backs up into `./backups` when it
  starts and then each 24 hours. `docker compose run --rm backup now` makes
  one at once.
- **NixOS**: the service `rescord-backup` backs up into
  `/var/lib/rescord-backup` each day. `services.rescord.backup` sets when,
  and for how many days, or turns it off.
- **The tarball**: copy `deploy/systemd/rescord-backup.service` and
  `rescord-backup.timer` to `/etc/systemd/system/`, and run
  `systemctl enable --now rescord-backup.timer`. It backs up into
  `/var/lib/rescord-backup`, with the `pg_dump` of PostgreSQL 18.

### Restore

Stop Rescord, give it an empty database with the same name and owner, and
restore the newest backup, or the dump that you name. Then start Rescord
with the same secrets.

With Docker Compose:

```sh
docker compose stop rescord
docker compose exec db psql -U rescord -d postgres \
  -c 'DROP DATABASE rescord' -c 'CREATE DATABASE rescord'
docker compose run --rm backup restore
docker compose run --rm rescord bin/reapply-erasures
docker compose start rescord
```

On NixOS:

```sh
systemctl stop rescord
runuser -u postgres -- dropdb rescord
runuser -u postgres -- createdb --owner rescord rescord
rescord-restore /var/lib/rescord-backup
systemctl start rescord
```

From the tarball, with the `rescord` function of the install steps:

```sh
sudo systemctl stop rescord
sudo -u postgres dropdb rescord
sudo -u postgres createdb --owner rescord rescord
rescord restore /var/lib/rescord-backup
sudo systemctl start rescord
```

To restore an older dump, give its name after the directory, such as
`rescord-20261120T020000Z.dump`.

A dump that is older than an erasure on request still holds the person
who was erased (ADR 0105). Each erasure writes a marker to the store,
with ids and no email, and `rescord-restore` and `rescord restore` read
the markers after the restore and erase each such person again, before
Rescord starts. With Docker Compose, `bin/reapply-erasures` above does
the same. It prints a count, and a second run changes nothing.

## Move the files to another store

`bin/move-storage` copies the files from the directory into a bucket of
S3, or from the bucket into the directory, for a server that changes
`RESCORD_STORAGE` (ADR 0059). It puts each file that the new store does
not have, reads it back, and compares it with the file of the old store. A
file that the new store has already is read and compared, and not copied.
It deletes nothing in either store, and it writes over no file that the
new store has.

The database needs no change: a record names its file by a key, which is
the same in both stores.

1. Make a backup, as "Back up" says.
2. Add the settings of the new store, and keep each setting of the old
   one. Do not change `RESCORD_STORAGE` yet. For a bucket, add each
   `RESCORD_S3_` setting, and make the bucket at the provider. For a
   directory, `RESCORD_FILES_DIR` is set already in each way of installing.
   The bucket can be empty or not: the command leaves each file that it
   does not know.
3. Copy the files, while Rescord runs. This is the long step. Each line
   below copies from the directory into the bucket; for the other
   direction, write `s3 disk`.

   - With Docker Compose, in a container of its own, which reads `.env`
     again:

     ```sh
     docker compose run --rm rescord bin/move-storage disk s3
     ```

   - On NixOS, as root, after you rebuild the machine with the new
     settings:

     ```sh
     rescord-move-storage disk s3
     ```

   - From the tarball, with the `rescord` function of the install steps:

     ```sh
     rescord move-storage disk s3
     ```

   The command prints what it did, and exits with 1 when a file is not
   copied:

   ```text
   The directory /var/lib/rescord/files has 1204 files, and the bucket rescord at https://t3.storage.dev has 0.
     100 of 1204
     ...
   copied  1204 files (2.31 GB), and read each one back

   Each file of the directory /var/lib/rescord/files is in the bucket rescord at https://t3.storage.dev.
   Nothing was deleted: the directory /var/lib/rescord/files keeps its files.
   ```

   When a line says `FAIL`, fix what it names and run the command again:
   it copies only what is missing. A run that stopped in the middle is
   safe to start again in the same way.
4. Set `RESCORD_STORAGE` to the new store, and start Rescord again
   (`docker compose up -d` with Docker Compose). Keep the settings of the
   old store.
5. Run the command of step 3 one more time. It copies each file that a
   person added between step 3 and step 4. Until then, the page of such a
   file does not show it. To have no such time, stop Rescord before step 3
   and start it at step 4: the command needs the two stores, and not the
   server or the database.
6. Run `bin/check`, and open a photo and a PDF in Rescord. `bin/check-files`
   then says whether the new store has each file that a record names (see
   "Check the files").

Keep the old store until the new one has served for a time, and then
delete it yourself. After a move to S3, the backup of each day no longer
copies the files: keep the bucket with the versions of its provider. After
a move to a directory, the next backup copies each file.

A name in the old store that Rescord did not make, such as the
`lost+found` of a volume, stays there, and the report names it. The
command does not move the files of one bucket into another bucket: move
them through a directory.

## Check the files

`bin/check-files` compares the files of the store with the records of the
database (ADR 0091). It changes nothing: it deletes no file, and it writes
no record. Run it while Rescord runs, in the way of your install:

```sh
docker compose exec rescord bin/check-files     # Docker Compose
rescord-check-files                             # NixOS, as root
rescord check-files                             # the tarball, with the `rescord` function of the install steps
```

It lists each file of the store that `RESCORD_STORAGE` names, reads the
tables that name a file in each organisation, and prints a report:

```text
The directory /var/lib/rescord/files has 1207 files (2.31 GB), and Rescord has 3 organisations.

named     1204 files (2.31 GB) that a record names
leftover  2 files (3.4 MB) that no record names
  5b0c9d0e-8a57-4c58-9a57-1f0e3f1f6f0a/photos/0d8f2c36-5f0c-4d55-a8a4-0d8b7a1f2c11  3.4 MB
  5b0c9d0e-8a57-4c58-9a57-1f0e3f1f6f0a/thumbnails/0d8f2c36-5f0c-4d55-a8a4-0d8b7a1f2c11  9.2 kB
other     1 that Rescord did not put there: lost+found

A leftover is a file that an upload or a transfer put in the store before it failed.
A file of an upload that runs now can be in this list too. Run the command
again: a leftover is in both runs.
The store has each file that a record names.
Nothing was changed.
```

- **named**: the files that a record names: a photo, a file of a journal
  entry, a receipt of an expense, or a file of a transfer that a refuge
  received. A removed record and an old version of a record count, because
  the history still shows their files.
- **leftover**: a file of an organisation that no record names. Rescord
  puts a file in the store a moment before it saves the record. When that
  save fails, the person sees an error, and the file stays in the store.
  No page shows it, and it does no harm: it takes space. Rescord deletes
  no leftover. To have the space back, delete the keys of the report with
  the tools of the store, after a second run named them again.
- **unknown**: a file under a first segment that is no organisation of
  this server, such as the test file of a `bin/check` that stopped, or
  the files of another server in the same bucket.
- **other**: a name that is no key of Rescord, such as the `lost+found`
  of a volume.
- **FAIL**: a file that a record names, and that the store does not have.
  The page that shows it gives an error. The line names the key, the kind
  of the record, its id and the id of its organisation. Look for the key
  in a backup of the store, and put the file back under the same key.

The report names the first 20 files of a group, and
`bin/check-files --all` names each one. It prints ids, keys and sizes,
and nothing that a person typed.

The command exits with 0 when the store has each file that a record
names, with leftovers or with none, with 1 when a file is missing, and
with 2 when it could not compare the two: the store did not list its
files, the database did not answer, or a migration of this version has
not run.

It reads no file, so it does not find a file with the wrong bytes. With a
bucket it sends one request for each 1000 files. Good times to run it:
after a restore, after `bin/move-storage`, and when the store grows more
than the records explain.

## Change the secret of the keys

`RESCORD_KEY_SECRET` encrypts what Rescord keeps secret in its database:
the private keys of the transfers between servers, and the key of each
provider of the assistant. To give the server a new secret, for example
after a person who knew it has left:

1. Make a backup, and make the new secret: `openssl rand -base64 48`.
2. Put the new secret in `RESCORD_KEY_SECRET`, and the old one in
   `RESCORD_KEY_SECRET_PREVIOUS`. Start Rescord again. It now reads what
   either secret encrypted, and encrypts with the new one.
3. Run `bin/rotate-vault`, in the way of your install:

   ```sh
   docker compose exec rescord bin/rotate-vault     # Docker Compose
   rescord-rotate-vault                             # NixOS, as root
   rescord rotate-vault                             # the tarball, with the `rescord` function of the install steps
   ```

   It encrypts each value of the old secret again with the new one, and
   prints how many. It prints no secret. A second run changes nothing.
4. Run `bin/check`. Its line `vault` says when no value needs the old
   secret any more.
5. Take `RESCORD_KEY_SECRET_PREVIOUS` out, and start Rescord again. Keep
   the new secret with the backups. A backup from before the change needs
   the old secret: keep that one with those backups, until they are gone.

A value that neither secret opens stays as it is, and the command says so
and exits with 1. A key of a provider that does not open is typed again on
its page. The keys of the transfers of a refuge that do not open cannot be
made again by a command: restore the secret that encrypted them.

## The assistant, Ruby

Ruby is an optional assistant for the members of a rescue (ADR 0069).
Rescord works in full without it, and a server sends nothing to any
service of a language model until a root user sets one up. The work comes
in steps: this version has the settings of the server and of an
organisation, and the page where a member asks Ruby,
`/o/<organisation>/ruby`, which the bar at the top of each page links
to for a member who can ask it.

**Ruby has no setting in the environment**, and none in a file of the
server. A root user of Rescord sets it on the page `/root/ruby`:

1. Add a provider: the service that runs the model (Anthropic, Claude on
   Amazon Bedrock, Ollama on a machine of your own, or another server
   that speaks the chat API of OpenAI), the model, and the key of the
   service.
2. Press "Test". Rescord sends one small request with the word "ping" and
   no record of a rescue. It costs a part of a cent at a hosted service.
3. Tick "An organisation can choose this provider" when the test passes.

The page says where the records of a question go with each provider, in
the words that an administrator of an organisation reads before they
turn Ruby on.

**Each organisation turns Ruby on for itself.** A person whose role has
the power "Change the settings of the organisation" opens the settings
of the organisation, and then "The settings of Ruby". The page shows the
sentence of the provider that you offer, or a choice when you offer more
than one. Who turns Ruby on agrees to that place, and Rescord keeps the
sentence and the time. The page also has the allowance of a month, which
starts at the amount that you gave the provider, and the days that a
conversation is kept.

**A change of the place turns Ruby off.** When you change the address or
the region of a provider, the sentence changes. Ruby is then off for each
organisation that agreed to the old sentence, until a person there reads
the new one and agrees. The same holds when you stop offering a provider
or remove it. A new model, a new key or a new limit changes no sentence,
and turns nothing off. The page of a provider says how many organisations
have Ruby on with it, so read that number before you change the place.

**The key of a provider** is encrypted in the database with
`RESCORD_KEY_SECRET`. No page shows it again: only its last four
characters and the day that it was set. It is in no file, no log and no
history of Rescord.

- To change it, type the new key into the field of the provider and save.
  Then revoke the old key at the service: Rescord cannot do that.
- To remove a provider deletes its key from Rescord.
- Set a spend limit at the service too, for the account or the workspace
  of the key. It holds whatever Rescord counts.
- A backup of the database holds the key in its encrypted form. Without
  `RESCORD_KEY_SECRET` nobody opens it.

## Notifications on devices and on ntfy

A member gets a notification when somebody tells them about a comment, or
comments on a record that they follow (ADR 0106). Each one is on the page
of notifications of the organisation, and the bell in the site bar counts
them. That needs nothing from you.

A notification can also reach a phone or a computer, through the push
service of its browser (Web Push), and a topic of ntfy. Both are off
until a root user turns them on, on the page `/root/push`. **None of it is
in the environment.**

**What leaves the server** is the name of the organisation, one sentence
("Somebody told you about a comment.") and the address of the page of
notifications. It names no resident, no person and no word of a comment.

### Web Push

1. Open `/root/push` and press "Make the keys". The private key is
   encrypted in the database with `RESCORD_KEY_SECRET`, and no page shows
   it.
2. Give a contact: an address that starts with `mailto:` or `https://`.
   The push services of Apple, Google, Mozilla and Microsoft can write to
   it about the notifications of your server.
3. Tick "Send notifications to devices" and save.

Each person then turns notifications on for each of their devices, on
the page of notifications. Rescord sends only to the push services of the
browsers, over HTTPS: your server needs to reach `fcm.googleapis.com`,
`*.push.services.mozilla.com`, `*.push.apple.com` and
`*.notify.windows.com` on port 443.

- Web Push needs Rescord served over HTTPS. A browser offers no push to
  a page over plain HTTP.
- On an iPhone or an iPad, a person adds Rescord to the Home Screen
  first (Share, then "Add to Home Screen"), and turns notifications on
  in the app that opens from there. The page says so.
- **New keys end each subscription.** Make them only when the private key
  may have left the server. Each person then turns notifications on
  again, on each device.
- A device that the push service no longer knows is removed by itself.

### ntfy

[ntfy](https://ntfy.sh) sends a notification to its app on a phone or a
computer. Use ntfy.sh, or a server of ntfy of your own.

1. On `/root/push`, give the address of the server, which starts with
   `https://`, tick "Send notifications to ntfy", and save.
2. If your server of ntfy lets only its users write, make an access token
   for a user that can write to all topics (the names are random), and save it under "The access
   token of ntfy". It is encrypted in the database, and no page shows it
   again. ntfy.sh needs none.

Each person who wants it presses "Get notifications on ntfy" on the page
of notifications, and subscribes to the address that the page shows in
the ntfy app. The name of the topic is random, and anybody who knows it
can read the topic: that is why it gets only the sentence. A person can
renew the name, or stop.

## Upgrade

1. Make a backup, as "Back up" says, and copy it from the server.
2. Read the section "Upgrade notes" of each release after yours in
   `CHANGELOG.md`, up to the one that you install, the oldest first, and
   do what each one says. The notes name each migration that the start
   will run, and say whether it runs in the database or in each
   organisation and what it does to your data. A step that you do by
   hand is there in full: "Before the upgrade" comes before step 3, and
   "After the upgrade" comes after step 5.
3. Take the new version.
   - With Docker Compose, put the new version in `RESCORD_IMAGE`, and run
     `docker compose pull` and `docker compose up -d`.
   - On NixOS, put the tag of the new version in the URL of the input, run
     `nix flake update rescord`, and rebuild the machine.
   - From the tarball, stop Rescord, and unpack the new tarball over
     `/opt/rescord`.
4. Start Rescord. Each start runs the migrations that have not run, for the
   database and for each organisation, and then the server starts. Before
   it changes anything, the start rehearses the upgrade: see below.
5. Run `bin/check`: its first line says the version that runs.

You can upgrade past several releases in one step: the start runs the
migrations of each of them, in order. Stop at a release between only when
its upgrade notes say so.

### The rehearsal of an upgrade

A start with migrations that have not run first rehearses them (ADR 0081).
It runs each one, for the database and for each organisation, in a
transaction that it takes back. So an upgrade runs each migration two
times, and the first start of a new version takes longer than a start.

When the rehearsal passes, the log says so, and the migrations run:

```text
The rehearsal of the upgrade passed: 1 migration of the database, and
6 migrations in 2 organisations. Nothing is changed yet. Rescord runs the
migrations now.
```

When a migration fails in the rehearsal, Rescord changes nothing and does
not start. The log names the migration and the organisation, with the
message of PostgreSQL:

```text
The rehearsal of the upgrade failed, and Rescord changed nothing.
It tried 6 migrations in 2 organisations.

20261128054817_add_ruby_conversations, in the organisation wattle-creek (org_...):
  relation "ruby_messages" already exists
```

Then:

1. Put the old version back, and start it: the database is as it was, so
   you need no restore. With Docker Compose, the container of the new
   version starts again and rehearses again until you do; each rehearsal
   changes nothing.
2. Find the name of the migration in the "Upgrade notes" of its release.
   Its line says what the migration does, and which step it needs, such
   as "Before the upgrade". Do the step, and upgrade again.
3. If the notes do not explain the failure, it is a fault of Rescord:
   please report it at <https://github.com/rellen/rescord/issues>, with
   the lines of the log and with no data of your rescue. Stay on the old
   version until a release puts it right.

You can rehearse before the day of the upgrade. The command changes
nothing, and exits with 1 when a migration fails. While it runs, the pages
of an organisation wait for the tables that it holds, so choose a quiet
hour:

```sh
docker compose run --rm rescord bin/migrate --rehearse   # Docker Compose, with the new version in RESCORD_IMAGE and after `docker compose pull`
rescord-migrate --rehearse                               # NixOS, as root: the version that is installed
/opt/rescord-new/bin/migrate --rehearse                  # the tarball of the new version, unpacked beside the old one, with the settings of the service
```

`bin/migrate --no-rehearsal` migrates with no rehearsal. Use it only when
the upgrade notes of a release say so.

### After the rehearsal

The migrations that run after the rehearsal change the database for the
new version, and the old version may not run on it. To go back, restore
the backup of step 1.

The rehearsal cannot see each fault: a server that stops in the middle of
the migrations, or a disk that is full. When a migration fails after the
rehearsal passed, Rescord does not start. The last line of the log that
starts with `== Running` gives the number and the module of the
migration, such as
`20261127182144 Rescord.Repo.TenantMigrations.ArchiveTaskSubjects`. The
upgrade notes name each migration with that number first, such as
`20261127182144_archive_task_subjects`. The migrations before it have
run, so restore the backup of step 1 before you start the old version
again, and please report the failure.
