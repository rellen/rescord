# ADR 0115: Security headers and the limits of input

Status: accepted (28 November 2026). The maintainer asked whether Rescord
validates what people type and keeps the pages safe from cross-site
scripting. A review of the code found no hole that a person can use; this
ADR records the second walls that the review added.

## Context

The review looked at each `raw/1` and `{:safe, _}`, the two Markdown
renderers (`RescordWeb.Markdown`, `RescordWeb.RubyMarkdown`), the CSV, ICS,
Typst and MJML output, the SQL fragments, redirects, CSRF, the sign-in,
the mail, Web Push, ntfy and the tools of Ruby. Each one escapes or checks
what people write. The gaps were behind that first wall:

- The pages had only the `Content-Security-Policy` of Phoenix
  (`base-uri` and `frame-ancestors`), so one future slip in a renderer
  would let a script run, or an image of another site carry data out.
- The session cookie had no `Secure` flag.
- An invitation sends an email, and a comment can send a notification to
  each member it tells, with no limit on either.
- The limit of sign-in links for one client counted each IPv6 address,
  and one home or server has a whole network of 64 bits.
- The socket of LiveView took a frame of any size (the default of
  Phoenix), and an address of a user had no length or shape.
- A prescription could end before it starts.

## Decision

- **A strict policy on each page** (`RescordWeb.SecurityHeaders`, in the
  pipeline `:browser`): `default-src`, `script-src`, `style-src`,
  `font-src`, `manifest-src` and `worker-src` are `'self'`; `img-src`
  adds `data:` for the drawings of the stylesheet; `connect-src` adds the
  socket at the address of the endpoint (`wss://` for `https://`), because
  an older browser does not take a socket as `'self'`; `object-src
  'none'`, `base-uri 'self'`, `form-action 'self'`, `frame-ancestors
  'self'`. No `'unsafe-inline'` and no `'unsafe-eval'`: the markup has no
  inline script, no inline style and no `style` attribute, and stays so.
  A `Permissions-Policy` turns off the camera, the microphone, the
  location, payment and USB for scripts. A controller that sends a file
  keeps its sandbox policy.
- **Oban Web** (ADR 0110), the page of a package with an inline script
  and `style` attributes, gets the same policy with a nonce of each
  response for its script and stylesheet (`csp_nonce_assign_key`), and
  `style-src-attr 'unsafe-inline'` for the widths of its bars. Only a
  root user opens it.
- **The session cookie is `Secure` in production**
  (`config :rescord, secure_session_cookie: true` in `prod.exs`, read at
  compile time like `:force_ssl`), and `HttpOnly` everywhere.
- **Rate limits** (ADR 0020, `AshRateLimiter`): one person invites 50
  people an hour, for both kinds of invitation together, and writes 10
  comments a minute.
- **The window of each rate limit slides** (`algorithm: :sliding_window` of
  Hammer): a limit of 30 a minute holds for any 60 seconds. The fixed
  window before started a new count at the turn of each period, so a
  person could make twice the limit across the turn, and a test that ran
  over the turn of a minute saw no limit (the reports test failed so in
  CI). The table keeps one row for each allowed call until its period
  ends; the limits are small, so the rows are few.
- **A rate limit of a client** counts an IPv4 address, or the IPv6
  network of 64 bits (`RescordWeb.ClientAddress.limit_key/1`), for the
  sign-in. The calendar feed keeps a count of each address: a calendar
  service asks for many people from few networks.
- **The socket takes a frame of 1 MB at most**: an event of a page, or a
  chunk of an upload (64 kB).
- **An address of a user and of an invitation** has one `@`, no space and
  254 characters at most. The check is of a new or changed address.
- **The last day of a prescription is on or after its first day**, on the
  entry and on the record of the prescription, so a correction that gives
  one day is held to the other.

## Consequences

- A new page that needs an inline script, an inline style or a file of
  another site breaks under the policy. Put the script or style in
  `assets/`, or change the policy here with a reason. The browser tests
  run each page under the policy.
- A self-hosted Rescord must be reached over HTTPS for a session (it is
  already: production sends plain HTTP to HTTPS). Safari does not keep a
  `Secure` cookie on `http://localhost`.
- The counts of the limits are of one node, and a restart forgets them,
  as ADR 0020 says.
- Left for a later decision: a monthly cap of Ruby for each person (the
  allowance is of the organisation), ranges for the values of a
  measurement by its kind, the bind address of the metrics port, limits
  on the lists of ids that some actions take, and the keys of maps in
  `AshTypst.Code`, which it does not escape (Rescord passes only atoms).
