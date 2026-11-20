# ADR 0046: The address of a client behind a proxy

Status: accepted (the maintainer, 20 November 2026).

## Context

The sign-in counts the requests of each client by its address (ADR 0020).
Each package of ADR 0044 puts a reverse proxy in front of Rescord, so each
connection came from the address of the proxy, and each person shared one
count. One client could use the count up and stop the sign-in for
everybody. ADR 0022 left the real address undecided.

## Decision

- **`RescordWeb.ClientAddress`**, a plug of the endpoint, puts the address
  of the client in `conn.remote_ip`, so the code that reads it does not
  change.
- **Only a trusted proxy says the address.** For a connection from another
  address, the plug ignores `X-Forwarded-For`.
- **The plug reads the header from the right**, and takes the first address
  that is not a trusted proxy. A proxy adds to the right of the header, and
  a client can write only to the left of it, so a client cannot choose its
  address. An entry that is not an address stops the search at the last
  trusted address.
- **`RESCORD_TRUSTED_PROXIES`** names the proxies, as addresses and networks:
  `127.0.0.0/8, ::1` by default, for the NixOS module and the systemd unit.
  The Compose file trusts the private networks, because only Caddy reaches
  Rescord there.
- **An IPv4 address in the form of IPv6** (`::ffff:a.b.c.d`) becomes the
  IPv4 address, so one client has one count.
- **No dependency.** The plug is about a hundred lines, and `remote_ip`
  would be a new package.

## Consequences

- Caddy and the nginx of the NixOS module send the header by default. Another
  proxy must add the address of the client to `X-Forwarded-For`, and a proxy
  on another machine goes in `RESCORD_TRUSTED_PROXIES`.
- In the Compose file, a client on the private network of the server can
  reach Caddy and name an address of its own in the header only if Caddy
  passes the header on. Caddy replaces it when it does not trust the client,
  which is its default.
- An entry with a port, such as `203.0.113.7:443`, is not an address, so the
  plug counts the proxy for it. Caddy and nginx write no port.
- Each address of IPv6 has its own count. A client with a network of IPv6
  has many addresses.
