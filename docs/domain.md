# The domain of Rescord

This document follows ASD-STE100 Simplified Technical English.

The maintainer gave the scope on 15 November 2026, and then answered
questions about it on that day and the next. Section 4 lists the answers. A paragraph that starts
with the word *Proposal* is an idea that the maintainer has not agreed yet.
Section 7 holds estimates, not measurements.

## 1. Purpose

Rescord is a management system for an animal rescue or an animal refuge. An
organisation uses Rescord to record its residents, the care that they get,
and its supplies.

## 2. Terms

| Term | Definition |
| --- | --- |
| organisation | A rescue or a refuge that uses Rescord. One organisation is one tenant. |
| user | A person who can sign in to Rescord. |
| member | A user who belongs to one organisation. One user can be a member of many organisations. |
| root user | A user who manages Rescord itself. A root user creates an organisation and invites its administrators. |
| administrator | A member who manages the members and the settings of one organisation. |
| resident | An animal that an organisation has in its care. |
| family | A named set of residents that came together or were born together, for example a litter. |
| parent link | A record that one resident is the mother or the father of another resident. |
| group | A set of residents that the organisation manages together, and that is not a family. |
| location | A place where a resident lives, or where the organisation keeps a lot. |
| journal | The list of the journal entries of one resident. |
| journal entry | One record that a member writes about a resident. It has a kind, for example an examination or a note about a placement. |
| medical history | The journal entries of a resident that have a medical kind. |
| addendum | A new journal entry that names an earlier journal entry, and adds to it. |
| timeline | The journal entries of a resident together with the changes that Rescord records, in order of time. |
| task | One piece of work that a member does for a resident, a group, or a location. |
| item | A type of supply that the organisation keeps, for example one brand of dry food. |
| lot | One delivery of an item. A lot can have an expiry date. |
| assistant | A part of Rescord that answers the questions of a member in a conversation, and prepares records for the member to confirm. Its name on the pages is Ruby. An organisation can leave it off. |
| conversation | The questions of one member to the assistant, and its answers, in order of time. |
| tool | One function of Rescord that the assistant can use to read records, or to prepare a record. A person writes the list of the tools. |
| proposal | A record that the assistant prepared and that Rescord has not written. Rescord writes it only when the member confirms it. |
| provider | A service that runs the language model of the assistant. A root user records it. |
| entity | An object that has an identity of its own, for example a resident. |
| dimension | A list of permitted values that describes an entity. The species is an example. |
| shared value | A value of a dimension that all organisations can use. |
| local value | A value of a dimension that one organisation added for its own use. |
| tie | A table that connects two or more entities. |
| temporal resource | A resource of Ash that keeps each version of a record, with the period for which the version is valid. |
| paper trail | A record of each change to a resource, with the member who made the change. AshPaperTrail keeps it. |
| archive | To mark a record as removed and keep its row. AshArchival does this. |
| resource | An Ash resource. One resource maps to one table of the database. |
| 5NF | Fifth normal form. The keys of a table in this form imply each way to divide the table with no loss of data. |
| 6NF | Sixth normal form. A table in this form holds a key and no more than one other attribute. |

## 3. Scope

These root entities are in scope:

1. users;
2. residents, with their arrival and their departure;
3. families of residents;
4. groups of residents;
5. locations of residents;
6. the journal of each resident, which holds its medical history;
7. tasks;
8. inventory.

These subjects are out of scope for now:

- adoption;
- foster care.

## 4. The answers of the maintainer

| Question | Answer |
| --- | --- |
| How many organisations will use Rescord? | Tens. |
| Which tenancy does Rescord use? | One schema of PostgreSQL for each organisation (ADR 0011). |
| Who owns the values of a dimension? | All organisations share a base list, and each organisation can add local values. |
| Where does Rescord store a local value? | In the schema of the organisation that added it. |
| Which facts about a resident need a history? | The name, the status, the desex status, and the weight and other measurements. |
| Is the departure of a resident in scope? | Yes: death, release, and transfer to another organisation. |
| What does a family record? | Both the parent links and a named set of residents. |
| Can one user work for more than one organisation? | Yes. |
| How does a location contain a location? | Each organisation defines its own kinds, and a location can be inside any other location. |
| Which other dimensions does a resident have? | Identifiers, size class, coat, temperament, and desex status. |
| What does a completed `medicate` task record? | The task, and a journal entry for the dose. It records no stock movement. |
| How does Rescord track the inventory? | By lot, with an expiry date, and by location. |
| Who writes a journal entry? | A member only. |
| Which tools keep the history? | The temporal resources of Ash, AshPaperTrail, and AshArchival (ADR 0012). |
| Which resources are temporal and keep a paper trail? | Each resource, by default (ADR 0013). A resource with a workflow is not temporal. |
| Can a member change a journal entry? | Yes, and the paper trail keeps the entry as it was. An addendum or a new journal entry is the preferred way. |
| What is the name of one record in the medical history? | A journal entry. The journal also holds entries that are not medical. |
| What does the journal hold about a change to a placement or a group? | Only what a member writes about it. The change itself stays in the resource that records it. |
| How does a person sign in? | With a link that Rescord sends by email. Rescord stores no password. |
| How does a person join an organisation? | By invitation only. A root user invites an administrator, and an administrator invites a member. |
| Who creates an organisation? | A root user. |
| Which levels does a user have? | A user is a root user or is not. Root is a level of the user, and it is not a role of a member. |
| Where does the first root user come from? | From a script that a person runs in IEx when Rescord is first deployed. |
| Can an administrator make another member an administrator? | Yes. |
| What can a root user do in an organisation? | Anything. A root user can read and change the data of each organisation. The conversations of the assistant are the one exception (ADR 0069). |
| Which library does the sign-in use? | AshAuthentication (ADR 0018). |
| Can the time of an answer show that an address has an account? | No. A request for a sign-in link runs in a task and answers at once, in each case (ADR 0019). |
| Which roles does a member have at the start? | Administrator and member. The grants can hold more roles later. |
| Does the model fit the housing of one organisation? | No. The location tree and the placement must serve each organisation. |
| What does a placement name? | A resident or a group. |
| Where does the description of a group come from? | Rescord calculates it from the links between residents, and a member can replace it. |
| Which values does the status of a resident have? | Expected, in care, away for a time, and left. The departure records how and why a resident left. |
| How does a routine repeat? | With a small set of patterns: each day at set times, on given days of the week, or after a number of days. |
| What does a reorder level apply to? | An item in the whole organisation, and also an item in one location when the organisation gives one. |
| Which part does the project build first? | The sign-in and the organisations. |
| Which service sends the email of a sign-in and of an invitation? | An SMTP service that the operator chooses (ADR 0044). |
| How does a page name its organisation? | In the path, and not in a subdomain. The path starts with `/o/` and the short name of the organisation. |
| How does a resident name a value of a dimension? | The list of the organisation holds each value that the organisation uses. A resident names a row of that list (ADR 0025). |
| How does a resident get its status? | Rescord calculates it from the arrival, the departure and an absence. A member sets only `away for a time`. |
| Which dimensions have a fixed list? | The eight of section 7.3. The size class and the coat are lists that an organisation can extend. |
| Which part does the project build second? | The residents: all of section 5.2. |
| In which order does the project build the other parts? | Families and groups, locations, the journal, tasks, and then the inventory. |
| Must a resident have a breed, a colour, a size class and a coat? | No. An organisation that wants `not known` adds it to its list. |
| Who removes a resident that was recorded by mistake? | An administrator. The removal archives the record, and ends its ties to groups, families and relatives (ADR 0036). It ends its placement too, and takes the resident out of each task and each routine. The tasks stay (ADR 0067). |
| How does an organisation remove a value from a list? | It retires the value. A resident that has the value keeps it, and no form offers it for a new choice. The organisation can bring it back. |
| Must a parent be a resident of the organisation? | Yes. A parent that did not live there is a resident with no arrival. |
| Can a resident be in more than one group at one time? | Yes. Each membership has its own start and end. |
| Where does a resident live when it and its group each have a placement? | In its own placement, while that lasts. After it ends, the resident is with its group again. |
| Does a location have a capacity? | It can have one. A placement over the capacity is permitted, and the page says so. |
| Can a member say when a thing happened? | Yes, for an absence, a placement, a change to a group, a journal entry, and a stock movement. The time is now when the member gives none, and it is never after now. |
| Who corrects a journal entry? | Its author, and an administrator. Each other member writes an addendum. |
| How does a task become complete? | A task is due, done, or skipped. A task names a member or is for each member. Each member can take an open task, complete it, or skip it with a reason. |
| How far ahead does Rescord make the tasks of a routine? | A number of days that is a setting, 14 at the start. A member can also plan a task or an event for a date months ahead, one time or with a pattern, as on a calendar. |
| Where will Rescord run? | The maintainer has not decided, and the work does not wait for it. |
| In which time zone is an organisation? | In the zone that is its setting (ADR 0026). A root user gives it when they create the organisation, and an administrator can change it. |
| How does a page write a date, a time and a number? | In the forms of the language and region of the organisation, which is a setting (ADR 0075). A root user gives it when they create the organisation, and an administrator can change it. The words of a page are English. |
| Which units can a measurement have? | Each kind of measurement lists the units that it accepts, and the form offers only those (18 November 2026). |
| Does Rescord know what a unit means? | Yes, for a unit of its catalogue, by the name of the unit: `kg` is a mass, and Rescord converts it. A unit that only the organisation knows, such as `bag`, stays a name (ADR 0071). |
| Can a use of stock take more than the record has? | Yes. The level can go below zero, and the item shows a warning until a member records a count. |
| When does a lot expire soon? | In a number of days before its expiry date. Each category of item has its own number. A category with no number uses 30 days. |
| What does "every number of days" count from? | Each routine says it: from its first day, as a calendar, or from the last time that a member completed its task. |
| Can a routine have its own number of days ahead? | Yes. The organisation has a default, and a routine can have its own number. |
| Who starts, changes and ends a routine? | An administrator. A member works through the tasks. An administrator also keeps the items and the suppliers. |
| Can a refuge see a resident that another refuge transferred to it? | Yes, as a copy that it cannot change. The copy holds the facts and the medical history. The first refuge can add other parts. |
| Can a journal entry have an attachment? | Yes. The files are in storage that is compatible with S3. |
| Can a task name more than one member? | Yes. The task is done when one of them completes it. |
| Which parts does the copy of a transferred resident hold, other than the facts and the medical history? | The parts that the first refuge chooses. An administrator gives the default parts as a setting, and a member can change them for each transfer. |
| Which library reads the storage of the attachments? | `req_s3`, a plugin of `Req`. The maintainer approved it. |
| Which parts can a refuge add to the copy of a transferred resident? | The other journal entries, the stay, the placements, the families and the groups, and the photos with the albums and the profile picture. |
| To which refuge can a refuge transfer a resident? | To a partner. An administrator asks another refuge by its short name, and it becomes a partner when an administrator there accepts. No member sees a list of the other refuges. |
| Must the receiving refuge accept a transfer? | Yes. Nothing appears there until a member with that power accepts it, and it can decline. |
| Does the copy of a transferred resident change later? | No. It holds the record as it was at the transfer. |
| Who records, accepts and reads a transfer? | An administrator records it and accepts it. Each member reads the copy. |
| Which service stores the attachments? | Tigris in production, probably. A machine for development runs Garage, and the tests use a store in a temporary directory (ADR 0038). |
| Who defines the roles of an organisation? | Its administrators. Each organisation starts with an administrator and a member. An administrator can add a role, and give it what it may do. |
| What does an import of a transfer file from another server make? | A received transfer: a copy that waits for an answer, as a transfer on one server does (19 November 2026). |
| How does a refuge know that a transfer file is true? | The refuge that sends it signs it, and encrypts it for the refuge that receives it. |
| From whom can a refuge import a transfer file? | From a partner on another server that it recorded. |
| Does a transfer file carry the photos and the PDFs? | Yes. The file is one archive with the copy and its files. |
| Does Rescord have an assistant? | Yes, with the name Ruby (ADR 0069, 28 November 2026). It is off until a root user records a provider and an administrator of the organisation turns it on. Rescord is complete without it. |
| With which rights does the assistant work? | With the rights of the member who asks, and never with the rights of a root user. |
| Can the assistant write a record? | No. It prepares a proposal, and the member confirms it. Then the member wrote the record. |
| Does the assistant give veterinary advice? | No. It says what the records hold. |
| Who reads a conversation? | Its member, and the administrators of the organisation, who cannot change it. Rescord tells each member so. A root user who is not an administrator there does not read it. |
| How long does Rescord keep a conversation? | For a number of days that the organisation sets, 90 at the start. Then Rescord deletes it. Its member can delete it before that. |
| Where is a setting of Rescord? | In a resource, with a page, unless Rescord needs the setting before it can reach its database, before the first person can sign in, or the setting describes the machine (ADR 0068). A secret in a resource is encrypted. |

## 5. The root entities

### 5.1 Users

A user is a person who can sign in to Rescord. All organisations share the
users. A member connects one user to one organisation.

- A person signs in with a link that Rescord sends by email. Rescord stores
  no password.
- A person joins an organisation by invitation only.
- A root user is a user who manages Rescord itself. A root user creates an
  organisation, and invites its administrators.
- An administrator invites the members of the organisation, and can make
  another member an administrator.
- A root user can do anything in each organisation: read its data and change
  it. A root user is not a member of the organisation. The paper trail names
  the root user who made a change.
- Root is a level of the user. It is not a role of a member, and it does not
  belong to one organisation.
- At the start a member has one of two roles: administrator or member. An
  administrator also manages the members and the settings of the
  organisation.

A member has one role of the organisation (ADR 0040). The administrators
define the roles, and tick what each one may do: a role has powers, and a
power is one area of work, such as the journal or the routines. Each role
reads what the organisation has. A person gives only the powers that their
own role has. The role of the administrators keeps the power to change the
roles. The section "Policies and roles" of `docs/architecture.md` describes
the grants.

The first root user comes from a script that a person runs in IEx when
Rescord is first deployed. No page makes the first root user.

The record of a user says that the user is a root user, and its paper trail
keeps each change. After the first one, a root user can make another user a
root user. The last root user stays one.

The script calls `Rescord.Accounts.bootstrap_root/1` with an email address.
A release has no Mix, so a person calls the function from the remote shell
of the release. The function does nothing when Rescord has a root user.

An invitation makes the user and the member, and sends an email that says
where to sign in. The email has no token: the person asks for a sign-in
link. A job sends the email after the invitation is saved, and sends it
again after a fault of the mail server, for about 18 hours (ADR 0067).

### 5.2 Residents

A resident is an animal in the care of an organisation. A resident has these
dimensions:

| Dimension | Example values | How many a resident has |
| --- | --- | --- |
| species | dog, cat, horse, hen | one |
| sex | female, male, not known | one |
| breed | kelpie, domestic short hair | one or more |
| colour | black, tan, tabby | one or more |
| size class | small, medium, large | one |
| coat | short, long, wire, rough with rosettes | one |
| temperament | shy, reactive to dogs, needs an experienced handler | zero or more |
| desex status | entire, desexed, not known | one, with a history |
| identifier kind | microchip, ear tag, leg band, tattoo | one for each identifier |

- Rescord keeps a history of the name, the status, and the desex status of a
  resident. The name and the desex status are each a temporal resource in
  6NF. The history of the status comes from the resources that Rescord
  calculates it from.
- The species, the breed, the colour, the size class, the coat, the
  temperament and the identifier kind are lists that an organisation can
  extend. The sex and the desex status are fixed lists.
- The weight is a measurement in the journal, so it has a history already.
- An arrival records how and when a resident came to the organisation. A
  departure records how and when a resident left.
- The age is not a dimension. Rescord calculates the age from the date of
  birth.

The arrival kinds are: surrender by an owner, stray, seizure by an
authority, birth in care, and transfer from another organisation. The
departure kinds are: death, release, and transfer to another organisation.
The code has these lists (ADR 0025). The maintainer has not changed them.

The status of a resident has a fixed list of four values: expected, in care,
away for a time, and left. The departure records how and why a resident left.

Rescord calculates the status at the instant of a read, and does not store
it:

1. A resident with a departure has left.
2. A resident with no arrival is expected.
3. A resident with an absence at that instant is away for a time.
4. A resident is in care in each other case.

An absence is the record that a member makes for the value `away for a
time`. Its period is the time away. An arrival and a departure are facts
that happened, so their dates are not after today. Today is the date in the
time zone of the organisation.

Rescord has these parts of this section (ADR 0025): the resident and each of
its dimensions, the name and the desex status with their history, the
identifiers, the arrival, the departure and the absence, and pages for them.

### 5.3 Families of residents

Rescord records the relatives of a resident in two ways:

- A parent link records that one resident is the mother or the father of
  another resident. Rescord calculates the other relatives from the parent
  links.
- A family is a named set of residents, for example a litter that arrived
  with no known parent.

A parent is a resident of the organisation. A parent that did not live there
is a resident with no arrival. A resident has one mother and one father at
most, and a resident is not a parent of one of its own parents. Rescord has
this section (ADR 0028).

### 5.4 Groups of residents

A group is a set of residents that is not a family. A bonded pair, a herd, a
flock, and a set of residents in quarantine are examples.

A group has a description, for example `sisters and a male that is not a
relative`. Rescord calculates the description from the parent links and the
families of the members. A member can replace the description with other
words.

A group has a group kind, from a list that the organisation can extend. The
membership of a resident in a group has a start and an end, and a resident
can be in more than one group at one time. Rescord has this section
(ADR 0028). The words for a group are `sisters and an unrelated male`: the
sex of a resident, and not a word of its species.

### 5.5 Locations of residents

Each organisation defines its own kinds of location. A unit, a bay, a level,
a room, a `building`, and a campus are examples. A location can be inside any
other location.

- Rescord holds one entity, the location, and one dimension, the location
  kind.
- A tie records which location contains a location. A change to the
  hierarchy of an organisation thus needs no migration.
- A placement records that a resident or a group lives in a location from
  one date to another date.
- The model does not fit the housing of one organisation. Rescord has no
  special record for two units that an organisation joins.

A location cannot contain itself, directly or through other locations.
Rescord rejects such a tie.

A resident with a placement of its own lives there while it lasts. In each
other case it lives with its group. A location can have a capacity, and a
placement over it is permitted: the page says so. Rescord has this section
(ADR 0029).

*Proposal.* A group that uses two units has its placement in the location
that contains both units.

### 5.6 The journal of a resident

The journal of a resident is the list of its journal entries. A member
writes each journal entry, and each journal entry has a kind. The medical
history of a resident is the part of its journal that has a medical kind.

The author of a journal entry, and an administrator, can correct it. The
paper trail keeps each version of the entry, and shows who corrected it and
when. Each other member writes an addendum. There are two preferred ways
to add to a journal entry:

- Write an addendum. An addendum is a new journal entry that names the
  entry that it follows.
- Write a new journal entry with no such link.

Use a correction only for a mistake in the entry.

Rescord has the journal (ADR 0030): an entry with the facts of its kind, the
time that the thing happened, an addendum, and a correction. It has the
timeline (ADR 0035). An entry has files: a photo or a PDF, which a person
attaches when they write the entry (ADR 0041).

A journal entry has one of these kinds:

| Kind | Part of the medical history |
| --- | --- |
| examination | yes |
| diagnosis of a condition | yes |
| measurement, for example the weight | yes |
| procedure | yes |
| vaccination | yes |
| prescription of a medication | yes |
| dose of a medication that a member gave | yes |
| placement | no |
| group | no |
| behaviour | no |
| general | no |

#### A change to a placement or a group

Rescord records such a change in the resource that holds the fact. A move of
a resident is a new version of its placement, with the date, the action, and
the member who made it. The journal does not record the change again.

- A member can write a journal entry of the kind `placement` or `group` about
  the change, for example to give the reason for a move.
- The timeline of a resident shows its journal entries together with the
  changes that Rescord records, in order of time.

*Proposal.* Such a journal entry names the placement or the group that it is
about. A change can also hold a short reason on its own version, with no
journal entry.

### 5.7 Tasks

A task is one piece of work. The maintainer gave these kinds of task, and
there can be many more:

- feed;
- medicate;
- clean;
- groom.

When a member completes a `medicate` task, Rescord also writes a journal
entry for the dose. It does not change the inventory.

A task has zero subjects or more. A subject is a resident, a group, or a
location. A task is due, done or skipped, and AshStateMachine holds the
states (ADR 0032). A task that names a prescription writes the journal entry
for the dose when a member completes it.

A routine is a task that repeats. A routine repeats with one of a small set
of patterns: each day at set times, on given days of the week, or after a
number of days.

Rescord has the routine (ADR 0033). A routine has one of four patterns: each
day; on given days of the week; every number of days; every number of
months. It has from 1 to 12 times of the day, in the time zone of the
organisation. Rescord makes the tasks of a routine a number of days ahead:
14 at first, which an administrator changes in the settings. A routine can
have a number of its own, up to 400, for a thing of the calendar such as a
check each year. A member also plans a task that does not repeat for any
day.

A routine of every number of days counts from its first day, as a calendar,
or from the day when a member last completed or skipped one of its tasks.
The routine says which (ADR 0039). A routine of the second kind has the
tasks of one day that are due at most, and its next day comes when a member
finishes the last of them.

Only an administrator starts, changes, pauses and ends a routine (ADR
0039). A task names zero members or more. A task that names none is for
each member. When one of its members completes a task, it is done for all
of them. A member who takes a task joins the members that it names.

A member can read the tasks in a calendar application (ADR 0074). The
member makes a calendar feed: an address that the calendar application
reads again and again. The feed holds the tasks that the member chooses.
It can also hold the days on which residents are expected back, and the
expiry dates of the stock. The calendar application only reads. A member
completes a task in Rescord.

### 5.8 Inventory

The inventory is the set of supplies of an organisation. The maintainer gave
these categories of item, and there can be many more:

- food;
- `bedding`;
- medication;
- `cleaning product`;
- `cleaning tool`.

Rescord tracks each lot of an item, with its expiry date, and the location
that holds it.

*Proposal.* A stock movement records that a quantity of a lot came into a
location or went out of it. Rescord does not store the stock level. It
calculates the level from the stock movements. A member records each stock
movement by hand.

A reorder level is the quantity below which the organisation orders more. It
applies to an item in the whole organisation. An organisation can also give
an item a reorder level in one location.

Rescord has the inventory (ADR 0034). A movement out can take the level of
a lot in a place below zero, and the item then asks for a count (ADR 0039).
A member who finds another number on the shelf records a count, and
Rescord writes the difference. A place is a location, or no place in
particular. A lot expires soon in the days before its expiry date that the
category of its item gives, or in 30 days. Stock that is past its expiry date does not count
against a reorder level.

An item that is a medication can have a strength (ADR 0072): the mass of
the medication in each millilitre or in each tablet, from the label. The
dose calculator of the tools can use it (section 5.12).

### 5.9 Transfers between refuges

A refuge sends a resident to a partner refuge as a copy that does not
change (ADR 0042). An administrator asks another refuge by its short name,
and the two are partners when an administrator there accepts. An
administrator sends a resident to a partner. The copy holds the facts and
the medical history of the resident, and the parts that the sender ticks:
the other journal entries, the stay, the placements, the families and the
groups, and the photos with the albums and the profile picture (ADR 0057).
The settings of the refuge tick the parts at first.

Nothing appears at the partner until an administrator there accepts the
transfer, and that administrator can decline it. After the acceptance, each
member there reads the copy. The refuge that sends a resident records its
departure itself. Here, an administrator is each role with the power
`:transfers`.

A partner can be on another Rescord server (ADR 0043). The two refuges
exchange partner cards and check their fingerprints, and an administrator
then exports a resident as a file, which is signed by the refuge that sends
it and encrypted for the one that receives it. The file holds the photos and
the PDFs of its entries. The other refuge imports it, and it waits for an
answer as a transfer on one server does.

### 5.10 Photos of a resident

A resident has photos (ADR 0055). Each photo has a date and an optional
caption. A member puts a photo in albums: an album is a named set of the
photos of one resident, and a photo can be in many albums or in none. One
photo of a resident can be its profile picture. The page of the resident
shows it, and the list of the residents shows it beside the name.

The photos of the journal entries of a resident are also its photos. Each
one shows the date of its entry and a link to the entry. A member can put
such a photo in an album, or make it the profile picture. Rescord then
keeps one record for it and no second copy of the file.

Rescord removes the metadata of each photo before it keeps the photo. The
metadata of a photo from a phone can hold the place where somebody took it,
for example the house of a foster carer. Rescord also turns the photo as
the camera recorded, and makes a small copy for the pages.

The power `residents` adds the photos and changes them. A member removes
the photos that they added. The power `remove_residents` removes each
photo. A photo of the journal leaves the photos when a member takes it off
its entry.

### 5.11 The assistant

Rescord has an assistant with the name Ruby (ADR 0069). It is optional. A
root user records a provider, and an administrator turns the assistant on
for the organisation. The page that turns it on says where the records go.

A member asks a question in a conversation. The assistant uses tools to
read the records of the organisation, with the rights of that member, and
answers in a few sentences. Each fact in an answer comes from a tool, and
the answer has a link to each record that a tool read. The assistant gives
no veterinary advice.

The assistant writes no record. When a member tells it a thing that
happened, the assistant prepares a proposal. The page shows the proposal
as a card, with the record as Rescord will write it. The member confirms
the proposal, changes it, or discards it. A record from a confirmed
proposal has the member as its author, and its paper trail says that the
assistant prepared it. Some records never have a proposal: a member, a
role, a setting, a removal, a departure, a transfer, a routine, a
correction of the entry of another person, a prescription, a diagnosis, a
procedure and a vaccination.

The power `ruby` lets a member use the assistant. An organisation has an
allowance for each month, and the assistant stops when the allowance is
used.

A conversation belongs to its member. The administrators of the
organisation can read it and cannot change it, and the page of the
assistant says so. A root user who is not an administrator of the
organisation cannot read it. Rescord deletes a conversation after the
number of days that the organisation sets, and when its member removes
it. A conversation is not in the export of the data.

### 5.12 Tools

An organisation has tools (ADR 0072). A tool helps a member with a piece
of work. It is not a record, and it stores nothing. Each member of the
organisation can use each tool.

The dose calculator is the first tool. A member types the weight of an
animal, the dose rate for each kilogram, and the strength of the product.
The calculator gives the dose, and the volume or the number of tablets
that holds the dose. It shows each step of the arithmetic.

A member can take the weight from the journal of a resident. The
calculator then shows the date of that measurement and its age in days.
When the journal has more than one measurement that can be a body weight,
the member chooses one.

A member can also take the strength from an item of the inventory that
has one. The calculator names the item, and tells the member to check the
strength against the label. It says when the records have no stock of the
item that is in date.

The calculator knows no medication. It gives no dose rate, and it does not
say that a dose is safe. The dose rate and the strength come from a vet or
from the label. The page tells the member to check the result with a vet.

### 5.13 Reports

An organisation makes reports for paper (ADR 0076). A report is a PDF. It
is not a record, and Rescord keeps no copy of it. Each member can make
each report, and a report holds what that member can read.

- The record of a resident has its facts, its stay, its family and its
  groups. The member chooses the part of the journal: the medical history,
  all of it, or none. The member can add the photos. The record names no
  member, because it can leave the refuge.
- The cage card is one page for the door of a pen.
- The register lists each resident in care on a day. A resident is in
  care on a day when it arrived on or before that day and did not leave on
  or before that day.
- The report of the arrivals and the departures covers a period. It gives
  the totals by kind and by species.
- The task sheet lists the tasks of a day, with a box to tick for each.
- The stock report lists each item with its lots, with a column for a
  count.
- The housing report lists each location with the residents that live
  there.

## 6. Design rules

The maintainer asked for a design in 5NF and 6NF.

1. Each table is in 5NF.
2. An attribute gets a table of its own, in 6NF, when the organisation needs
   its history. Such a table is a temporal resource: it holds the key, the
   period for which the value is valid, and the value. Section 4 names the
   attributes.
3. A dimension that an organisation can extend has two resources. One holds
   the shared values, and all organisations read it. The other holds the
   local values, in the schema of the organisation.
4. A dimension with a fixed list of values is an enumerated type, and it is
   not a resource. Section 7.3 lists them.
5. A relation of many to many is a tie.
6. Rescord stores a fact one time and calculates the other values. The age,
   the stock level, and the relatives of a resident are examples.
7. Each resource is a temporal resource and keeps a paper trail, unless the
   resource states the opposite. `Rescord.Resource` sets these defaults
   (ADR 0013).
8. A temporal resource keeps its paper trail on its own rows. Each version
   then says which action made it, and who did so.
9. Rescord deletes no row that a member removes. It archives the row. The
   conversations of the assistant are the one exception: Rescord deletes
   them (ADR 0069).
10. A resource with a workflow, such as a task, is not a temporal resource.
    The compiler refuses a resource that is both. ADR 0012 gives the reason.

## 7. Estimate of the resources

This section applies the answers of section 4 and the proposals of sections
5 and 6. Each name is one resource. A different decision changes the count.

### 7.1 The resources in the schema of each organisation

| Area | Resources | Count |
| --- | --- | --- |
| Access | `Member`, `Role`, `MemberRole`, `Grant` | 4 |
| Residents | `Resident`, `ResidentName`, `Absence`, `ResidentDesexStatus`, `ResidentBreed`, `ResidentColour`, `ResidentTemperament`, `ResidentIdentifier`, `Arrival`, `Departure` | 10 |
| Families and groups | `ParentLink`, `Family`, `FamilyMember`, `Group`, `GroupMember` | 5 |
| Locations | `Location`, `LocationParent`, `Placement` | 3 |
| Journal | `JournalEntry`, `Diagnosis`, `Measurement`, `Procedure`, `Vaccination`, `Prescription`, `Dose`, `Attachment` | 8 |
| Tasks | `Task`, `Routine`, `TaskResident`, `TaskGroup`, `TaskLocation`, `TaskAssignee`, `RoutineResident`, `RoutineGroup`, `RoutineLocation` | 9 |
| Inventory | `Item`, `Lot`, `Supplier`, `StockMovement`, `ReorderLevel` | 5 |
| Lists of the organisation | one for each of the 15 dimensions of section 7.2 | 15 |
| **Total** | | **59** |

### 7.2 The dimensions that an organisation can extend

There are 15: `Species`, `Breed`, `Colour`, `SizeClass`, `Coat`,
`Temperament`, `IdentifierKind`, `GroupKind`, `LocationKind`, `Condition`,
`MeasureKind`, `ProcedureKind`, `TaskKind`, `ItemCategory`, and `Unit`.
Rescord has each one.

The maintainer decided that each has shared values and local values, and
that a local value is in the schema of its organisation (ADR 0016). Each
dimension thus has two resources:

| Resource | Where it is | What it holds |
| --- | --- | --- |
| The base list | Outside the schemas. All organisations share it. | The shared values. |
| The list of the organisation | In the schema of each organisation. | Each value that the organisation uses: a shared value by reference, or a local value. |

- Each schema holds 15 lists, one for each dimension. They are in the
  count of section 7.1.
- All organisations share 18 resources: the 15 base lists, `Organisation`,
  `User`, and the token of a sign-in.
- The maintainer rejected the other way: one shared resource for each
  dimension, where a local value names the organisation that owns it. That
  way has 15 fewer resources in each schema. It keeps the local values of
  all organisations in one table.

The list of an organisation holds each value that the organisation uses
(ADR 0025). A row of the list names a value of the base list, or it is a
local value with a name of its own. It is never both. A resident thus names
one table for its species, and that table is in the same schema.

- A root user adds a shared value to a base list, and can give it a new
  name.
- An administrator adds a shared value to the list of the organisation, and
  adds a local value. An administrator can give a local value a new name.
- An administrator retires a value. A resident that has the value keeps it,
  and no form offers it for a new choice. An administrator can restore it.

### 7.3 The dimensions with a fixed list

These 8 dimensions are enumerated types, and they are not resources. The
maintainer decided that the size class and the coat are not among them:

- sex;
- desex status;
- kin role;
- kind of journal entry;
- route of a medication;
- reason for a stock movement;
- arrival kind;
- departure kind.

### 7.4 The resources that a paper trail adds

A paper trail adds resources in two ways (ADR 0012):

- On a temporal resource, the paper trail is on the rows of the resource. A
  version resource lists the versions, and it reads the same table. It thus
  adds one resource and no table.
- On each other resource, the paper trail adds one version resource and one
  table.

With the defaults of rule 7, each of the 59 resources has a version resource.
Only a resource with a workflow is not temporal, and thus adds a table.
`Task` is the only such resource in this estimate.

| | For each organisation |
| --- | --- |
| Resources, with the version resources | 118 |
| Tables | 60 |

AshArchival adds one column to a resource. It adds no resource and no table.

### 7.5 The size of the database

Each table makes about 3 or 4 relations in PostgreSQL: the table, its
indexes, and a store for long text. Thus the 60 tables of one organisation
make about 200 relations. For 50 organisations, the database holds about
3,000 tables and about 10,000 relations. That quantity gives PostgreSQL no
difficulty.

### 7.6 The resources that Rescord has

Rescord has each part of section 3. This table counts the resources of the
code on 16 November 2026. It is smaller than the estimate of section 7.1.

| Area | Resources | Count |
| --- | --- | --- |
| Access | `Member` | 1 |
| Residents | the 10 of section 7.1 | 10 |
| Families and groups | the 5 of section 7.1 | 5 |
| Locations | the 3 of section 7.1 | 3 |
| Journal | the 8 of section 7.1 but `Attachment` | 7 |
| Tasks | `Task`, `TaskSubject`, `Routine` | 3 |
| Inventory | the 5 of section 7.1 | 5 |
| Lists of the organisation | one for each of the 15 dimensions | 15 |
| **Total** | | **49** |

The differences from the estimate:

- A role is an attribute of the member, and the grants of a role are in the
  code (ADR 0024). The estimate had 3 resources for them.
- A journal entry has no attachment yet.
- One resource, `TaskSubject`, says what a task is for (ADR 0032). The
  estimate had one for each kind of subject. A task names one member, with
  no resource for that. A routine names its subjects in lists of ids
  (ADR 0033).

`Member`, `Task`, `TaskSubject` and `Routine` are not temporal, so each has
a table for its versions. Thus each organisation has 98 resources with the
version resources, and 53 tables. All organisations share 18 resources, as
section 7.2 says.

Rescord has 10 enumerated types: the 8 of section 7.3, the status of a
resident, and the pattern of a routine. The state of a task is a state of
its state machine.

## 8. Open points

1. Which other kinds of task and categories of item are necessary?
2. Which resources, other than a resource with a workflow, are not temporal
   resources or keep no paper trail?
