# ADR 0070: The emails are MJML with EEx, with a text part

Status: accepted (the maintainer asked for it on 28 November 2026; the
design is issue 4, and the look is a first choice).

## Context

Rescord sends three emails: the sign-in link, the invitation to an
organisation, and the test email of `bin/check`. Each was plain text,
written where it was sent. The maintainer asked for emails with the look
of the application, made with the package for MJML and EEx.

The HTML of an email is not the HTML of a page. A mail program takes out
most of a stylesheet, and some draw a page with the engine of a word
processor. An email that looks the same in each of them is made of nested
tables, with the styles on each element. MJML is a language that writes
that HTML from a few elements such as a section, a column and a button.

## Decision

- **`Rescord.Mail` builds each email.** It has one function for each
  email, which takes plain values and returns a `Swoosh.Email` with the
  sender of the settings, the subject, an HTML part and a text part. The
  caller delivers it with `Rescord.Mailer`. The settings of the mail
  server do not change (ADR 0044, ADR 0068).
- **The HTML part is MJML with EEx**, with `mjml_eex` and the Rust NIF
  `mjml` (`mrml`). There is no Node. `lib/rescord/mail/layout.mjml.eex`
  is the layout, and each email has a template with the content of its
  card, and a module beside it.
- **The build compiles the MJML** (`mode: :compile`). A send only fills in
  the values. A template can thus use a value as text or as the value of
  an HTML attribute, and no `if` or `for` around an MJML element.
- **Each value is escaped.** `mjml_eex` renders with `Phoenix.HTML.Engine`.
  The name of an organisation and the address of an inviter come from a
  user.
- **The text part is written by hand**, in the module of the template, and
  says the same as the HTML part. It is not made from the HTML.
- **`Rescord.Mail` is a boundary of its own**, a sibling of the core. The
  module of a template calls `Phoenix.HTML`, which the core may not use
  (ADR 0009). The boundary uses no other one. `Rescord.Accounts`,
  `Rescord.Release` and `RescordWeb` name it in their `deps`.
- **The markup of an email is not classless.** ADR 0004 is for the pages
  of the application. An email has the tables, the inline styles and the
  classes that MJML writes, and a few classes of ours (`rs-`), which the
  dark scheme needs to find an element. The rule that a template does keep
  is the one of ADR 0015: it writes no colour but a value of
  `assets/css/layers/tokens.css`.
- **The look is Scrubs** (ADR 0015): the ground `bg`, a card of `surface`
  with an edge and corners of 12px, the mark and the name above it, one
  heading, one action as a pill in `accent`, the address of the link as
  text below a rule, and a note in `muted` below the card. The test email
  has a state as a shape and a word. The width is 600px at most, in one
  column.
- **Light and dark.** The inline styles are the light scheme. A media
  query on `prefers-color-scheme` holds the dark scheme, and the head
  states `color-scheme: light dark`.
- **An email loads nothing.** It has no image, no font file and no
  stylesheet of any host. The mark is a small table with an edge and a
  plus of three cells, and not an image: an SVG does not show in Gmail or
  Outlook, an image on the server waits until the person allows images and
  needs the address of the server in the core, and an attached image shows
  as an attachment in some programs. The typeface is Atkinson
  Hyperlegible on a device that has it, and then the stack of the
  application. The stack leaves Ubuntu out, because MJML fetches Ubuntu,
  Roboto, Lato, Open Sans and Droid Sans from Google Fonts when a stack
  names one.
- **Accessibility.** The document has a language and a title. Each email
  has one `<h1>`. The layout tables have `role="presentation"`. The mark
  is `aria-hidden` beside the name as text. The words of a button say what
  it does, and the button is 48px high. The body text is 16px. Each pair
  of a text and its ground is one that `RescordWeb.TokensTest` holds to
  WCAG AA in both schemes.
- **`Rescord.Mail.previews/0` has each email with example values.** The
  tests use it, and with `dev_routes` the pages under `/dev/mail` show the
  HTML part and the text part of each one, beside the mailbox of Swoosh.
- **The builds.** `rustler_precompiled` downloads the native library of
  `mjml` from the release of that package and checks it against the
  checksums in the Hex package. The devenv shell, CI, the image and the
  tarball build so. The Nix package has no network in its build:
  `nix/package.nix` fetches the file by its hash and puts it where
  `rustler_precompiled` looks first, as it does for MDEx.
- **`rustler_precompiled` is 0.8.4.** `mjml` 5.3 asks for `~> 0.8.3`, and
  `mdex_native` for `~> 0.8`. `mjml_eex` 0.13 does not take `mjml` 6, which
  allows a newer one.

## Consequences

- An email looks like Rescord, in a light and in a dark mail program, and
  a person who reads plain text gets the same words.
- A mail program that does not read the media query shows the light
  scheme, or changes the colours itself, as Gmail on a phone and Outlook
  do. Outlook for Windows draws the mark and the card with square corners.
- Nobody has looked at the emails in Gmail, Outlook or Apple Mail yet.
  The pictures of the design are from Chromium in both schemes. A send
  from a server to those programs is the next check.
- A new email is a template, a module, a function in `Rescord.Mail` and an
  entry in `previews/0`. `Rescord.MailTest` then holds it: both parts, the
  language, the title, one heading, no file of another host, and the
  colours of `tokens.css`.
- The mark has a third drawing, after the icon of the site bar and the
  favicon (ADR 0058). A change to the mark is a change to the three.
- A value of `tokens.css` that changes must change in the layout by hand.
  The test fails until it does.
- The build needs the native library of `mjml` for the machine that
  builds. The package has one for Linux on x86_64 and on aarch64, with
  glibc 2.34 or later and with musl, and for macOS.
- When the version of `mjml` changes in `platform/mix.lock`,
  `mjmlNative` in `nix/package.nix` changes too: its version and its two
  hashes.
- `mjml_eex` 1.0 is a release candidate. A move to it also moves `mjml` to
  6 and frees `rustler_precompiled`.
