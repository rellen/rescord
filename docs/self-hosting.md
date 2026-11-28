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
`rescord-move-storage` (see "Move the files to another store") and
`rescord-rotate-vault` (see "Change the secret of the keys"). Each runs
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
ok    mail       smtp.example.org:587 takes the connection with STARTTLS, and the user rescord
ok    vault      each of the 3 encrypted values opens with the secret of this server
note  assistant  no provider yet. A root user adds one at /root/ruby
ok    email      sent to you@example.org: look for it in that inbox, and in its spam

Rescord is ready.
```

- **database**: Rescord reaches the database of `DATABASE_URL`, which is
  PostgreSQL 18 or later.
- **migrations**: a note, and no fault, when some have not run: the next
  start runs them.
- **store**: Rescord puts a small file in the store, reads it, and deletes
  it.
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
- **email**: with an address, Rescord sends a short email to it. When the
  email does not arrive, ask the provider of the SMTP server, and check
  the SPF and DKIM records of the domain of `RESCORD_MAIL_FROM`.

No line shows a password or a key.

## The settings

Rescord reads each setting from the environment when it starts. A required
setting that is missing, and a setting with a value that Rescord does not
take, stop the start with the name of the setting.

| Setting | Required | Default | What it is |
| --- | --- | --- | --- |
| `DATABASE_URL` | yes | | The database, as `ecto://USER:PASSWORD@HOST/DATABASE`. Add `?socket_dir=/run/postgresql` for a login over the local socket. |
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
| `RESCORD_S3_ENDPOINT` | with `s3` | | The address of the service, such as `https://s3.example.org`. |
| `RESCORD_S3_REGION` | no | `auto` | The region that the service asks for. |
| `RESCORD_S3_BUCKET` | with `s3` | | The bucket. |
| `RESCORD_S3_ADDRESSING` | no | `path` | Where the bucket goes in each address: `path`, as in `https://s3.example.org/rescord/...`, or `virtual`, as in `https://rescord.s3.example.org/...`. Garage and MinIO take `path` as they are set up by default. Tigris needs `virtual`, with the endpoint `https://t3.storage.dev` and the region `auto`. |
| `RESCORD_S3_ACCESS_KEY_ID` | with `s3` | | The key of a user that may read and write the bucket. |
| `RESCORD_S3_SECRET_ACCESS_KEY` | with `s3` | | Its secret. |
| `RESCORD_PHOTO_SLOTS` | no | `2` | The number of photos that Rescord works on at the same time (ADR 0056). A photo of a phone takes about 150 MB while Rescord turns it and removes its metadata, and the largest photo about 300 MB. More photos wait for their turn. Give a server with more memory a larger number. |
| `POOL_SIZE` | no | `10` | The number of connections to the database. |
| `RESCORD_BACKUP_KEEP_DAYS` | no | `14` | The number of days that a backup keeps a dump of the database (see "Back up"). |
| `ECTO_IPV6` | no | `false` | `true` to reach the database over IPv6. |

`GET /health` answers `ok` while Rescord and its database work, and the
Docker image and the Compose file use it.

The assistant has no setting here, and no other setting of this list is
for it (see "The assistant, Ruby").

## Back up

Each way of installing backs Rescord up by itself, each day (ADR 0050). A
backup is a dump of the database, with the schema of each organisation,
and a copy of each new file of the store. A dump is kept for 14 days,
`RESCORD_BACKUP_KEEP_DAYS`. A bucket of S3 is not copied: keep it with the
versions of its provider.

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
6. Run `bin/check`, and open a photo and a PDF in Rescord.

Keep the old store until the new one has served for a time, and then
delete it yourself. After a move to S3, the backup of each day no longer
copies the files: keep the bucket with the versions of its provider. After
a move to a directory, the next backup copies each file.

A name in the old store that Rescord did not make, such as the
`lost+found` of a volume, stays there, and the report names it. The
command does not move the files of one bucket into another bucket: move
them through a directory.

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
in steps: this version has the settings of the server alone, and no
member can ask Ruby anything yet.

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
   database and for each organisation, and then the server starts.
5. Run `bin/check`: its first line says the version that runs.

A migration changes the database for the new version, and the old version
may not run on it. To go back, restore the backup of step 1.

You can upgrade past several releases in one step: the start runs the
migrations of each of them, in order. Stop at a release between only when
its upgrade notes say so.

When a migration fails, Rescord does not start. The last line of the log
that starts with `== Running` gives the number and the module of the
migration, such as
`20261127182144 Rescord.Repo.TenantMigrations.ArchiveTaskSubjects`. The
upgrade notes name each migration with that number first, such as
`20261127182144_archive_task_subjects`: its line says what the migration
does, and which step it needs. The migrations before it have run, so
restore the backup of step 1 before you start the old version again. If
the notes do not explain the failure, it is a fault of Rescord: please
report it at <https://github.com/rellen/rescord/issues>, with the lines of
the log and with no data of your rescue.
