# ADR 0018: The sign-in uses AshAuthentication

Status: accepted (chosen by the maintainer, 15 November 2026)

## Context

A person signs in to Rescord with a link by email, and joins an organisation
by invitation only (`docs/domain.md`, section 5.1). The sign-in is the first
part of the domain that we build. It needs a library, or code of our own.

AshAuthentication is the extension of Ash for the sign-in. It has a strategy
for a link by email, which it names `magic_link`, and a resource for the
tokens.

We read the releases and the packages on the day of this record:

- The stable line is `ash_authentication` 4.15 and
  `ash_authentication_phoenix` 2.17. The lines 5.0 and 3.0 are release
  candidates.
- `ash_authentication` 4.15.1 needs `assent` 0.2.13, for a sign-in through
  another service. `mix deps.get` names an advisory of critical severity on
  that version (CVE-2026-117656): a callback of "Sign in with Apple" can
  replace a claim of the token. The corrected `assent` is 0.3.2 or later,
  which the stable line does not accept.
- The pages of `ash_authentication_phoenix` have Tailwind classes.

## Decision

- The sign-in uses `ash_authentication`, on its stable line.
- It uses the strategy `magic_link` only. Rescord has no password, and no
  sign-in through another service.
- The strategy makes no account for an address that it does not know: a
  user exists only after an invitation.
- We write the pages of the sign-in ourselves, as classless markup
  (ADR 0004). We do not use the pages of `ash_authentication_phoenix`.

## Consequences

- The advisory on `assent` stays in the output of `mix deps.get` while we are
  on the stable line. Rescord cannot reach the fault: it has no strategy for
  another service. Never add such a strategy on this line. Move to the line
  5.0 when it is released, and read its advisories first.
- The link reaches a person by email, so the sign-in works outside
  development only after the mailer is set up (`docs/architecture.md`,
  "Sign-in and organisations").
- Not tested yet, and each is a question for the first step of the work:
  - The user and the token are shared resources (`shared?: true`). The
    changes of AshAuthentication are probably not temporal safe, as those of
    AshStateMachine are not (ADR 0012). The user then states
    `temporal?: false`.
  - A token is not a fact of the domain. It probably needs no paper trail and
    no archive.
  - A mail program can open a link before the person does. The strategy has
    an option, `require_interaction?`, that asks for a press of a button
    first.
  - Whether we need `ash_authentication_phoenix` at all, for its plugs and
    its routes, when we do not use its pages.
- A root user, who creates an organisation and invites its administrators,
  is our own code. AshAuthentication knows only the user.
