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
- A place for the photos and the PDFs of the journal: a directory of the
  server, or a bucket of a service that is compatible with S3.

## Install

### With Docker Compose

`deploy/compose` holds the Compose file, a Caddyfile and `env.example`.

1. Copy `deploy/compose` to the server, and copy `env.example` to `.env`.
2. Fill in `.env`. Make each secret with `openssl rand -base64 48`.
3. Point the name of the server at it, and open the ports 80 and 443.
4. Start Rescord:

   ```sh
   docker compose up -d
   ```

5. Make the first root user, and ask for a sign-in link on the sign-in page:

   ```sh
   docker compose exec rescord bin/bootstrap-root you@example.org
   ```

The volume `db` holds the database, and the volume `files` holds the files.

### On NixOS

Add the flake of Rescord to the flake of the machine:

```nix
{
  inputs.rescord.url = "github:rellen/rescord";

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

The module installs `rescord-bootstrap-root`, which makes the first root
user with the environment of the service. Run it as root:

```sh
rescord-bootstrap-root you@example.org
```

`nix flake check` also runs a NixOS test of the module, which is slow
without KVM.

### From the tarball, with systemd

The tarball holds the release and its Erlang runtime. It runs on a system
with glibc 2.36 or later and OpenSSL 3: Debian 12 and later, Ubuntu 24.04
and later, and Fedora 37 and later. `scripts/release-tarball.sh` builds it.

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
6. Make the first root user, with the settings of the service:

   ```sh
   sudo systemd-run --pipe --wait --uid=rescord \
     --property=EnvironmentFile=/etc/rescord/rescord.env \
     --setenv=RESCORD_FILES_DIR=/var/lib/rescord/files \
     --setenv=RELEASE_DISTRIBUTION=none \
     /opt/rescord/bin/bootstrap-root you@example.org
   ```

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
| `RESCORD_KEY_SECRET` | yes | | A secret of 32 bytes or more, which guards the private keys of the transfers between servers (ADR 0043). Keep it with the backups. |
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
| `POOL_SIZE` | no | `10` | The number of connections to the database. |
| `ECTO_IPV6` | no | `false` | `true` to reach the database over IPv6. |

`GET /health` answers `ok` while Rescord and its database work, and the
Docker image and the Compose file use it.

## Back up

A backup of Rescord has three parts. Keep them together, and try a
restore on another machine one time.

1. **The database**, with `pg_dump`. It holds each organisation in a schema
   of its own, and `pg_dump` takes them all:

   ```sh
   pg_dump --format=custom --file=rescord.dump rescord
   # With Docker Compose:
   docker compose exec -T db pg_dump -U rescord --format=custom rescord > rescord.dump
   ```

2. **The files**: the directory of `RESCORD_FILES_DIR`, or the bucket. A
   file never changes after Rescord writes it, so a copy that adds the new
   files is enough.
3. **The secrets**: the environment file or `.env`. Without
   `RESCORD_KEY_SECRET`, Rescord cannot open the keys of the transfers
   between servers, and each partner must record a new partner card.

To restore, stop Rescord, restore the database with `pg_restore` into an
empty database, put the files back, give the same secrets, and start
Rescord.

## Upgrade

1. Back up, as above.
2. Take the new version: `docker compose pull` or a new build, a new input
   of the flake, or a new tarball unpacked over `/opt/rescord`.
3. Start Rescord. Each start runs the migrations that have not run, for the
   database and for each organisation, and then the server starts.

A migration changes the database for the new version, and the old version
may not run on it. To go back, restore the backup of step 1.
