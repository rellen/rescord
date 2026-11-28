# ADR 0069: Ruby, an assistant that reads and drafts as the member

Status: accepted. The maintainer asked for the design on 27 November
2026, answered each of its questions on 28 November 2026, and said to
build it in four phases with no stop between them. It follows ADR 0068
(the settings), and adds to ADR 0009 (the boundaries), ADR 0010 (Oban),
ADR 0020 (the rate limits), ADR 0040 (the roles) and ADR 0054 (the
export). It states two exceptions: to "a root user can read and change
the data of each organisation" of `docs/domain.md`, and to design rule 9
there.

## Context

A carer works on a phone, with one hand, between two tasks. The pages of
Rescord answer "what does this resident need today?" in three or four
presses across the tasks, the journal and the housing, and a journal entry
is a form. The maintainer asked how a chat assistant, with the code name
Ruby, could work with AshAi.

Four facts of Rescord shape the answer:

- **Only a member writes a journal entry** (`docs/domain.md`, section 4),
  and each write has a paper trail that names who did it.
- **Each role reads what the organisation has**, and a power gives a
  change (ADR 0040). The policy of each resource is the one check
  `Rescord.Accounts.Checks.Granted`, after a bypass for a root user.
- **Each organisation is a schema** (ADR 0011), and **each rescue runs its
  own server** (ADR 0044). ADR 0068 says that the
  environment holds only what starts Rescord, and that each other setting
  is a resource with a page.
- **The web layer reaches data only through the code interface of a
  domain** (ADR 0009), and most useful reads are functions of a domain and
  not read actions: `Rescord.Tasks.day/2`, `Rescord.Inventory.stock/1`,
  `Rescord.Journal.timeline/2`.

`ash_ai` 1.5.6 turns an Ash action into a tool for a model, and runs the
loop of a model and its tools (`AshAi.ToolLoop`) with an actor and a
tenant. It reaches a provider through `req_llm`.

Three risks decide the shape: a wrong answer about the care of an animal,
a write that nobody meant, and data that leaves the server.

## Decision

- **Rescord has an assistant, Ruby, and it is optional.** A server with no
  provider and no key has no Ruby: no page, no menu entry, no call. An
  organisation has Ruby when an administrator turns it on. Rescord is
  complete without it.
- **Ruby acts as the member.** Each tool call passes the user of the
  session as the actor and the organisation of the path as the tenant.
  No tool call passes `authorize?: false`, and Ruby has no actor of its
  own. The model has no input for a user or an organisation.
- **Ruby never has the rights of a root user.** One module makes the
  actor of Ruby, and it turns the root level off, so the bypass of a
  policy never applies in a tool call. A root user who is a member of the
  organisation has the rights of the role of that member. A root user who
  is no member there gets no Ruby there.
- **Ruby never writes. It proposes, and the member confirms.** The loop of
  the model cannot run a tool that changes a record: a gate stops it, and
  the call becomes a proposal, kept and not yet run. The page shows the
  exact record on a card that code built, and not the model. When the
  member confirms, `Rescord.Ruby.confirm_proposal/2` runs that one call in
  the request of the member, with the member as the actor, through the
  same action of the domain as the form. So the policy, the validations
  and the paper trail are those of the form. A proposal runs one time at
  most. The version of the record says that Ruby drafted it.
- **A tool is a line that a person wrote.** A list names each tool that
  Ruby may use, with its tier. An action whose inputs are wider than what
  Ruby may send gets a narrow tool of its own, and no destroy action is a
  tool.
- **Some actions never have a tool**: the members, the roles, the
  settings, a removal, a departure, a transfer, a partnership, the export,
  a routine, a correction of an entry of another person, and a
  prescription, a diagnosis, a procedure or a vaccination. A test lists
  the tools and fails for a tool of such an action.
- **Ruby gives no veterinary advice.** The prompt says so, and the
  evaluation set holds it: no diagnosis, no choice of a treatment, no
  arithmetic for a dose.
- **A fact comes from a tool result, with a link.** A tool names each
  record with a reference such as `resident:<id>`, and the page turns a
  reference that it knows into a link. The page loads nothing else that
  the model names: no other address, and no image.
- **Text from a record is data.** A tool marks the text of a journal
  entry, a name and a caption as data. The copy of a received transfer,
  which another server wrote, is not the source of any tool at first.
- **The domain `Rescord.Ruby`** holds the conversation, its messages and
  the proposals, in the schema of the organisation, and the code that
  calls `ash_ai`. A reply holds its tool calls and their results. The web
  layer reaches the domain through its code interface, as any domain.
- **The loop runs in a job of Oban, and not in the page.** A reply is
  saved as it arrives, and the page hears of it through PubSub. So a reply
  survives a phone that locks and a connection that drops.
- **The power `ruby`** lets a member use Ruby. It decides who can spend
  the allowance, and not what a person can learn: each role reads already.
- **Ruby has no setting in the environment and none in application
  config** (ADR 0068). A provider is a row of
  `Rescord.Ruby.Provider`, in the shared schema: the service, the model,
  the address, the limits and the key. A root user sets it on a page.
  The first provider is Anthropic, through ReqLLM, with the model Opus
  5.5 until the evaluation set has run, and then the cheapest model that
  passes each bar of it. A provider can also be Claude on Amazon Bedrock,
  or a model on a machine of the rescue, which gets the read tools only.
- **The key of a provider is encrypted with AshCloak**, in the one vault
  of Rescord, whose key comes from the secret of the server. A page
  never shows a key again: only its last four characters and the day
  that it was set. One function of the domain decrypts it, for a request
  to the provider. The resource is not temporal, its paper trail leaves
  the encrypted attribute out, and to remove a provider empties the key.
  No key is in a file, in a repository or in a log.
- **How one rescue uses Ruby is a row of `Rescord.Ruby.Settings`**, in
  the schema of the organisation: on or off, the provider, the
  allowance, the days that a conversation is kept. A member with the
  power `settings` sets it. Later, a rescue can add a key of its own,
  for a hosted service whose hosts are fixed, and never for an address
  that an administrator types.
- **An administrator agrees to where the data goes.** The page that turns
  Ruby on names the destination. A change of the provider or of its
  address turns Ruby off in each organisation, until an administrator
  reads the new place and turns it on again.
- **One request has a fixed start.** The system prompt is one constant
  text for the whole server, with no name and no date in it. The name of
  the rescue, the role, the day and the time zone are in a header of the
  member's first message. Inside a conversation the tools, the prompt and
  the stored turns never change, because the provider's cache and the
  model's stored thinking both need the same start.
- **An organisation has an allowance for a month, and a member has a rate**
  (ADR 0020). Past either, Ruby says so and calls no provider. The
  allowance is in whole US cents, and a new organisation has one from the
  start: 20 US dollars, unless the root user gave the provider another
  default. One request has a limit of tokens, one answer has a limit, and
  one reply has a limit of steps. The person who has the account sets a
  spend limit at the provider as the backstop.
- **A conversation belongs to its member, and an administrator can read
  it.** A member with the power `settings` reads each conversation of
  the organisation and changes nothing in it, so that a rescue can
  answer for what its volunteers were told. Ruby says so to each member
  on its first page. No other member reads it, and the resources of Ruby
  have no bypass for a root user. That is an exception to "a root user
  can read and change the data of each organisation" of
  `docs/domain.md`: an operator who is no administrator of the rescue
  does not read the working notes of a member through Rescord. It
  is kept for a number of days that the organisation sets, 90 at the
  start, and the member can remove it. It is not in the export (ADR 0054), and
  `Rescord.Export.excluded/0` gives the reason: it is no record of the
  rescue, and each thing that Ruby helped to write is in its own resource.
- **A conversation is deleted for real**, at the end of its days or when
  its member removes it. It is not temporal, keeps no paper trail and is
  not archived. That is an exception to rule 9 of the design rules ("Rescord
  deletes no row that a member removes"): a conversation is the working
  notes of one person, and a promise to forget them must be true, the
  more so since an administrator can read them.
- **No photo, PDF, name or email address of a member, token or key goes
  to the provider.**
- **Rescord counts the use itself**: the questions, the tool calls, the
  tokens, the cost, the ratings and the proposals, in the database of the
  organisation. The use is a resource of its own, `Rescord.Ruby.Usage`,
  with counts and no text, so that it stays when a conversation is
  deleted. Each request goes through one module, which counts also a
  reply that was stopped or that failed. No other service gets the
  counts, and no log holds the text of a request.
- **No test calls a provider.** A scripted model answers in `mix test`. A
  separate run asks a real model the questions of the evaluation set
  against a seeded rescue, before a release.
- **The work comes in phases**: the groundwork, then reads, then writes
  that a person confirms, then more rows in the attention section of the
  first page (ADR 0065), which Ruby reads and words. Each phase is off
  after an upgrade until an administrator turns it on.

## Consequences

- Rescord gets its first dependencies that reach a service outside the
  server at the request of a page: `ash_ai`, `req_llm`, and with them
  `ash_json_api` and `open_api_spex`, which `ash_ai` requires. The hash of
  `fetchMixDeps` changes, and `platform/AGENTS.md` gets their usage rules.
- With Ruby on, the records that a question needs leave the server for
  the provider. That is new for Rescord. `docs/self-hosting.md` says it in
  plain words, and the settings page of the organisation too.
- A proposal is one more step than a write by the model, and one more
  resource. It is what keeps "only a member writes" true.
- A read that is a function of a domain needs a tool of its own, written
  by hand in `Rescord.Ruby`. So the tools are a list that the project
  writes and reviews, and not each action of each resource.
- The tools work on temporal resources: a spike ran a read, a create and
  an update. Ruby reads and writes now. A question about a past date
  needs a tool of its own, because the instant of a loop would also
  backdate a write.
- A conversation holds what the member typed and what the tools returned,
  so the schema of an organisation now holds free text about its work
  that is in no other resource. The retention bounds it.
- The count of the allowance is in the database, and the rate is in the
  memory of one node (ADR 0020). Rescord runs as one node today.
- The answers of a model change with the model. A change of the model in
  a provider can change how good Ruby is, and only the
  evaluation run shows it.
- What needs attention has its place on the first page (ADR 0065). A
  note to a person who is not on the page needs a channel out of
  Rescord, and Rescord has none. If it gets one, the channel is a
  resource with its token in the vault, by ADR 0068.

## Options that this record sets aside

- **The model writes with the tools of `ash_ai` directly**, as the member.
  It is less code. A wrong word of the model is then a wrong record that
  nobody saw first, and "only a member writes" is no longer true.
- **A service account for Ruby with its own role.** It could then do more
  or less than the person. Each difference is a way to leak or to
  surprise, and the paper trail would name Ruby and not a person.
- **Ruby as a separate program** that reaches Rescord through an MCP
  server or a JSON API. It keeps the model out of the release. It needs a
  second deployment for each rescue, a second sign-in, and its own pages,
  and a rescue that runs one small server will not run two.
- **No `ash_ai`: `req_llm` and tools written by hand.** It has fewer
  dependencies and full control. The project would write again the schema
  of each tool from its action, the loop and the checks that `ash_ai` has.
- **The generated chat of `mix ash_ai.gen.chat`.** It makes a domain with
  a conversation and a message, a response that an Oban trigger runs, and
  a LiveView or a LiveComponent with the classes of Tailwind and daisyUI.
  It is a model to read and not code to keep: the pages of Rescord are
  classless and have no LiveComponent, and its resources use
  `Rescord.Resource` in the schema of an organisation.
