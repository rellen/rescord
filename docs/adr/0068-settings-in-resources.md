# ADR 0068: The environment starts Rescord, and resources hold the rest

Status: accepted. The maintainer set the direction on 27 November 2026,
and agreed each part of this record on 28 November 2026: the three tests
for each setting, one source, the mail in the environment, the secret of
the vault, and a vault of Rescord's own. It changes ADR 0044, which read
each setting from the environment, and adds to ADR 0043 (the secret of
the server) and to ADR 0048 (the advisories of the dependencies). Nothing
moves with this record: ADR 0069 has the first resource that follows it.

## Context

Rescord reads each setting from the environment when it starts (ADR 0044),
through `Shoddy.Env` in `config/runtime.exs`. An operator can set 28 names
today. That was right for the first packages: one file of
variables, checked at the start.

It does not fit an integration with an outside service: a store of
files, a language model, a chat service. For those:

- The person who sets it up may have no shell on the server. A root user
  of Rescord is not always the person who edits the unit file.
- A change needs a restart.
- Nobody sees who changed a value, or when.
- A secret is in a file of the server, in the settings of a host, or in a
  secret of a repository, and each place has its own rules.
- A setting of one organisation cannot be in the environment at all.

The maintainer set the direction on 27 November 2026: an integration is
an Ash resource, its secrets are encrypted with AshCloak, and an
administrator sets it on a page. The maintainer also said that some
settings must stay in the environment so that Rescord can start, and that
the line between the two was not sharp. This record draws the line.

## Decision

### The rule

**A setting is in the environment only when one of three tests is true.
Each other setting is an Ash resource.**

1. **Before the database.** Rescord needs the value to reach its
   database, or to open what is encrypted in it. A value cannot be in the
   place that it opens.
2. **Before the first sign-in.** Rescord needs the value to accept the
   first request safely and to let the first person in: where it
   listens, which name it has, the secrets that sign a session and a
   sign-in token, and the mail. A person signs in with a link that
   Rescord sends by email, so a server with no mail has no way in, and
   the page that would set the mail is behind that sign-in.
3. **Of the machine.** The value describes this machine or this process,
   and not the work of a rescue. The check: restore the backup of last
   night on another machine. A value that must not come with the backup
   is of the machine.

A person who adds a setting asks the three questions in this order. With
three answers of "no", the setting is a resource, also when a variable
would be less work.

Four more rules keep the line sharp:

- **One source for each setting.** A setting is in the environment or in
  a resource, and never in both. Rescord has no order of "the resource
  wins over the variable", because nobody can then say which value is in
  use.
- **A secret that opens other secrets is not in the database.** That is
  test 1, said for a secret: the key of the vault stays in the
  environment.
- **A value in `config/*.exs` that no operator can set is code, not a
  setting**: the queues of Oban, the adapter of a test. The rule does not
  cover it.
- **A resource of settings has a page.** A setting that only IEx can
  change is not done.

### Each setting of today

| Setting | Test | Where it is after this record |
| --- | --- | --- |
| `DATABASE_URL` | 1 | The environment |
| `POOL_SIZE` | 1 and 3 | The environment |
| `ECTO_IPV6` | 1 and 3 | The environment |
| `RESCORD_KEY_SECRET` | 1 | The environment. It becomes the secret of the vault too (see "The vault") |
| `SECRET_KEY_BASE` | 2 | The environment |
| `TOKEN_SIGNING_SECRET` | 2 | The environment |
| `PHX_HOST` | 2 and 3 | The environment. A copy of the database on another server has another name |
| `PORT`, `PHX_SERVER` | 2 and 3 | The environment |
| `RESCORD_LISTEN_ADDRESS` | 2 and 3 | The environment |
| `RESCORD_TRUSTED_PROXIES` | 2 and 3 | The environment. It decides which address a limit of the sign-in counts, from the first request |
| `RESCORD_FILES_DIR` | 3 | The environment: a directory of this machine. The backup command reads it with no release running |
| `RESCORD_PHOTO_SLOTS` | 3 | The environment: it follows the memory of this machine |
| `DNS_CLUSTER_QUERY` | 3 | The environment: how the nodes of this server find each other |
| `RESCORD_SMTP_HOST`, `_PORT`, `_TLS`, `_USERNAME`, `_PASSWORD` | 2 | The environment. A person needs the mail to sign in |
| `RESCORD_MAIL_FROM`, `RESCORD_MAIL_FROM_NAME` | 2 | The environment, with the mail |
| `RESCORD_STORAGE` | none | **A resource**: which store is in use |
| `RESCORD_S3_ENDPOINT`, `_REGION`, `_BUCKET`, `_ADDRESSING`, `_ACCESS_KEY_ID`, `_SECRET_ACCESS_KEY` | none | **A resource**, of the server, with the secret key in the vault |
| `RESCORD_BOTH_STORES` | | It goes away. No operator sets it today, and the command that moves the files reads both stores from the resource |

The variables that a command of the release sets for itself
(`RESCORD_ROOT_ADDRESS`, `RESCORD_CHECK_ADDRESS`, `RESCORD_MOVE_FROM`,
`RESCORD_MOVE_TO`) and those of the backup script
(`RESCORD_BACKUP_KEEP_DAYS`) are arguments of a command. They are not
settings of the server, and the rule does not cover them.

So 21 names stay in the environment: 14 of the server and of the machine,
and the 7 of the mail. The 7 of the store of the files move, and one
goes away.

The mail is the one integration with an outside service that stays in
the environment. It is there by test 2, and not as an exception to the
rule: no other integration is needed before a person can sign in.

Two settings that are in a resource already stay there: the time zone of
an organisation, and the lists.

The private keys of the transfers (ADR 0043) are in the database already,
encrypted under `RESCORD_KEY_SECRET` by code of Rescord's own. They can
move to the vault later, and nothing here needs it.

### What a new integration does

A new integration starts as a resource, and never gets a variable: a
provider of a language model, a chat service (Slack, Matrix, Signal,
Telegram, WhatsApp), a webhook, an account at another service.

### Two levels, and who sets each

| Level | What is in it | Where the row is | Who sets it | The page |
| --- | --- | --- | --- | --- |
| The server | How this server reaches a service that its operator runs or pays: the store of the files, a provider of a model that the server offers | The shared schema | A root user | Under `/root` |
| The organisation | How one rescue uses a thing, and an account of its own at a service: on or off, an allowance, the room of its own chat service, a key of its own | The schema of the organisation | A member with the power `settings` | The settings of the organisation |

One limit on the second level: **an administrator does not name a host
that Rescord then calls.** A person who can type an address into a page
can make the server call a machine of its private network. So a setting
of an organisation picks a service from a list with fixed hosts. Where a
service needs an address of its own (a Matrix server), Rescord takes
`https` only, and refuses a private or a loopback address at each
request, not only when the setting is saved. A root user can name any
address, because a root user can do that with a shell too.

### The vault

- **AshCloak** (`ash_cloak ~> 0.5`, which has the fixes of August 2026
  for two security reports) encrypts each secret attribute of a settings
  resource. The attribute `api_key` becomes the column
  `encrypted_api_key`, and a calculation `api_key` that decrypts when
  code asks for it.
- **`Rescord.Vault`** is the one vault: a plain module over `:crypto`,
  with AES-256-GCM. AshCloak calls its two functions, `encrypt!/1` and
  `decrypt!/1`. Its key comes from `RESCORD_KEY_SECRET` through
  HMAC-SHA256 with a fixed label, so the vault and the keys of the
  transfers do not use the same key. No new variable.
- **Not the package `cloak`**, which the guide of AshCloak names for the
  vault. Version 1.1.4 has an open advisory with no fixed release
  (EEF-CVE-2026-95105, on its cipher AES-CTR). A vault with only AES-GCM
  is not reached by it, but `mix hex.audit` fails on it in CI (ADR
  0048). The transfers have encrypted with `:crypto` in the same way
  since ADR 0043. A vault of `cloak` ran too, and the maintainer chose
  the module.
- **A secret is write only on a page.** The field is empty each time. The
  page shows the last four characters and the day that the secret was
  set, from two plain attributes.
- **Only one function of the domain decrypts**, with `authorize?: false`
  and a mark in the context that the option `on_decrypt` of AshCloak
  checks. A page, a tool of the assistant and the export cannot load the
  calculation.
- **The key of the vault can change.** For the time of a change,
  `RESCORD_KEY_SECRET_PREVIOUS` holds the old secret (test 1). Each
  value starts with the id of its key, so the vault reads both, and
  writes with the new one. A command of the release, `bin/rotate-vault`,
  writes each encrypted value again, and wraps the keys of the transfers
  again. Then the operator removes the old variable. `bin/check` says how
  many values still have the old key.
- **A lost `RESCORD_KEY_SECRET`** loses each secret of the settings, as
  it loses the keys of the transfers today. The pages then ask for each
  secret again. The guide already says to keep the secret with the
  backups.

### The record of a change

- A settings resource keeps a paper trail, as each resource of Rescord
  does. A version says who changed which setting, and when.
- **No version holds a secret, not even encrypted.** The paper trail
  ignores the encrypted attribute. A change of a secret shows as a change of the day
  that it was set.
- A settings resource with a secret is **not temporal**: the history rows
  of a temporal resource would keep each old encrypted value.
- To remove a row empties its secret and archives the row. Rescord
  deletes no row, and the secret is gone.

### The sweep of the policies, and the scan for secrets

- Each action of a settings resource passes the sweep of ADR 0063. A
  resource of the server refuses all five actors of the sweep, because
  only a root user sets it. A resource of an organisation has a grant
  under the power `settings`.
- One more test for each encrypted attribute: no actor of the sweep, and
  no root user through a page, can load the decrypted calculation.
- One test reads each version row after a change of a secret, and each
  line of the log, and finds neither the secret nor its encrypted form.
- The scan of ADR 0064 needs no new rule. It has less to find: no secret
  of an integration is in a file of a server, in a workflow or in a
  repository of an instance. The tests use a text that is plainly no key.
- `config :phoenix, :filter_parameters` gets the name of each secret
  field, so that the log of a form holds none.

### A new server

1. The operator sets the variables of the three tests: the database, the
   name, the three secrets, the mail, and the directory of the files.
2. `bin/migrate`, then the server starts. The store is the directory of
   `RESCORD_FILES_DIR`, which is the default until a root user names
   another.
3. `bin/bootstrap-root you@example.org` makes the first root user, as
   today. Nothing about it changes.
4. The root user signs in with a link by email, as today. The page
   `/root` shows what is not set: the store, when it is not the
   directory, and each optional integration. Each has a button that
   tries it.

**When the mail breaks later**, the operator mends it where it is set:
in the environment, with a restart, as today. `bin/check` sends a test
email already. Rescord gets no second way in.

### A server that exists

- The release that moves a group of settings **imports them one time**.
  `bin/migrate` sees that the resource has no row and that the old
  variables are set, writes the row with the secret in the vault, and
  says so in one line.
- From then on Rescord does not read the old variables. `bin/check` names
  each one that is still set, and says to remove it. A set variable never
  stops the start, and never wins over the resource.
- The changelog has the upgrade note in the same release.

### The order of the moves

Nothing moves with this record. Each move is a release of its own, with
its own record of what the import does.

1. **New integrations** are resources from their first commit: the
   provider of the assistant first.
2. **The vault**, with the first resource that needs it.
3. **The store of the files**, last. A wrong value there hides each photo
   and each PDF, and the commands for the backup and for a move read the
   same settings.

## Consequences

- A person sets up an integration in Rescord, with no shell and no
  restart, and the paper trail says who did it.
- The environment of a server is stable: 21 names, which are the 14 of
  the server and of the machine, and the 7 of the mail. No new
  integration adds one.
- A server needs `RESCORD_KEY_SECRET` for more than the transfers. It was
  required already.
- The database now holds secrets of outside services, encrypted. A copy
  of the database without `RESCORD_KEY_SECRET` opens none. A copy with it
  opens each. The guide says to keep the two apart.
- A person who installs Rescord from a file alone, as with the NixOS
  module, sets the mail in that file as today. An S3 store can no longer
  be set there: the module sets the variables of the three tests, and a
  person sets the rest on a page.
- A release that moves settings changes what an operator does. It is a
  breaking change for the operator, and the version says so (ADR 0060).
- Rescord reads a setting from the database when it uses it. A change
  takes effect at the next use, with no restart. If that read is ever too
  slow, a cache with a message on each change is the answer, and not a
  variable.
- A repository that deploys an instance has fewer secrets to hold. It
  keeps the secrets of the three tests.

## Options that this record sets aside

- **The resource wins over the variable, and the variable is the
  default.** It keeps each old server working with no step. It also means
  two sources for one value for ever, and a page that shows a value that
  a variable may or may not replace.
- **The mail as a resource, with a printed sign-in link.** The first
  draft had it: `bin/bootstrap-root` printed a link for the first root
  user, who then set the mail on a page, and `bin/root-link` did the
  same on the day that the mail broke. It makes each integration a
  resource, with no exception to explain. The maintainer chose the
  environment, with the mail as the one integration that starts the
  server.
- **A file of settings that Rescord reads at each start**, for an install
  with no person. It is the environment again, with another name. A
  command that imports a file one time can come later, if a person who
  installs many servers asks for it.
- **The secrets of the sessions and of the sign-in tokens in the vault**,
  made by Rescord at the first start. It would remove two variables. They
  are needed before the first request (test 2), and a server that makes
  its own secrets is harder to restore.
- **A key for each organisation in the vault.** One key is enough while
  one operator runs the server. The option `vault` of AshCloak can take a function, so a key for each
  organisation stays possible later.
