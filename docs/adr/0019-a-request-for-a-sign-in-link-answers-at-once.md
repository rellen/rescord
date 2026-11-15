# ADR 0019: A request for a sign-in link answers at once

Status: accepted (asked for by the maintainer, 15 November 2026)

## Context

A person asks for a sign-in link with an email address (ADR 0018). The
request can go three ways:

- Rescord knows the address: it makes a token and sends the email.
- Rescord does not know the address: it sends nothing.
- A fault occurs, for example in the mail service.

The first way takes much longer than the second. A person who measures the
time of the answer can thus learn which addresses have an account, although
the words of the answer are the same. That is a timing attack. An account in
Rescord also says that a person works for a refuge.

## Decision

- **Each way runs in a task, and the request answers at once.** The request
  starts a supervised task with the address, and then gives its answer. It
  does not wait for the task.
- **The answer is the same in each way**: the same status, the same words,
  and the same redirect. It does not say whether Rescord knows the address,
  or whether the email left.
- The request does no work before it starts the task that depends on the
  address: no read of the user, and no check of the form of the address that
  can end the request early.
- The rule is for the request for a link. The page that takes the link must
  answer the person, so it cannot run in a task.

## Consequences

- The person who asks never sees a fault. Rescord must log each fault of the
  task, without the token and without the link.
- The time of the answer no longer shows the way. The number of tasks does:
  a flood of requests starts a flood of tasks. The supervisor of the tasks
  needs a limit, and the request needs a rate limit. Neither is decided.
- A test holds the rule. It asks for a link with a known address, with an
  address that Rescord does not know, and with a mail service that fails.
  It compares the three answers, and it shows that the answer does not wait
  for a mail service that is slow.
- The strategy of AshAuthentication already gives the same result for a known
  address and for one that it does not know. It still does its work before
  it answers, so the task is ours to add.
