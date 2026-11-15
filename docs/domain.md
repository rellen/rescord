# The domain of Rescord

This document follows ASD-STE100 Simplified Technical English.

The maintainer gave the scope on 15 November 2026, and then answered twelve
questions about it. Section 4 lists the answers. A paragraph that starts
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
| What can a root user do in an organisation? | Anything. A root user can read and change the data of each organisation. |
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
| Which service sends the email of a sign-in and of an invitation? | Postmark, through SMTP. |
| How does a page name its organisation? | In the path, and not in a subdomain. The path starts with `/o/` and the short name of the organisation. |

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

*Proposal.* A member has one or more roles, and a role has grants. The
section "Policies and roles" of `docs/architecture.md` describes the grants.

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
link.

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
| coat | short, long, wire, no coat | one |
| temperament | shy, reactive to dogs, needs an experienced handler | zero or more |
| desex status | entire, desexed, not known | one, with a history |
| identifier kind | microchip, ear tag, leg band, tattoo | one for each identifier |

- Rescord keeps a history of the name, the status, and the desex status of a
  resident. Each of the three is a temporal resource in 6NF.
- The weight is a measurement in the journal, so it has a history already.
- An arrival records how and when a resident came to the organisation. A
  departure records how and when a resident left.
- The age is not a dimension. Rescord calculates the age from the date of
  birth.

*Proposal.* The arrival kinds are: surrender by an owner, stray, seizure by
an authority, birth in care, and transfer from another organisation. The
departure kinds are: death, release, and transfer to another organisation.

The status of a resident has a fixed list of four values: expected, in care,
away for a time, and left. The departure records how and why a resident left.

*Proposal.* Rescord calculates three of the values. A resident is expected
before its arrival, in care after its arrival, and left after its departure.
A member sets the value `away for a time`.

### 5.3 Families of residents

Rescord records the relatives of a resident in two ways:

- A parent link records that one resident is the mother or the father of
  another resident. Rescord calculates the other relatives from the parent
  links.
- A family is a named set of residents, for example a litter that arrived
  with no known parent.

### 5.4 Groups of residents

A group is a set of residents that is not a family. A bonded pair, a herd, a
flock, and a set of residents in quarantine are examples.

A group has a description, for example `sisters and a male that is not a
relative`. Rescord calculates the description from the parent links and the
families of the members. A member can replace the description with other
words.

*Proposal.* A group has a group kind. The membership of a resident in a group
has a start date and an end date.

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

*Proposal.* A location cannot contain itself, directly or through other
locations. Rescord rejects such a tie.

*Proposal.* A group that uses two units has its placement in the location
that contains both units.

### 5.6 The journal of a resident

The journal of a resident is the list of its journal entries. A member
writes each journal entry, and each journal entry has a kind. The medical
history of a resident is the part of its journal that has a medical kind.

A member can correct a journal entry. The paper trail keeps each version of
the entry, and shows who corrected it and when. There are two preferred ways
to add to a journal entry:

- Write an addendum. An addendum is a new journal entry that names the
  entry that it follows.
- Write a new journal entry with no such link.

Use a correction only for a mistake in the entry.

*Proposal.* A journal entry has one of these kinds:

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

*Proposal.* A task has one or more subjects. A subject is a resident, a
group, or a location. AshWorkflow holds the states of a task.

A routine is a task that repeats. A routine repeats with one of a small set
of patterns: each day at set times, on given days of the week, or after a
number of days.

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
4. *Proposal.* A dimension with a fixed list of values is an enumerated type,
   and it is not a resource.
5. A relation of many to many is a tie.
6. Rescord stores a fact one time and calculates the other values. The age,
   the stock level, and the relatives of a resident are examples.
7. Each resource is a temporal resource and keeps a paper trail, unless the
   resource states the opposite. `Rescord.Resource` sets these defaults
   (ADR 0013).
8. A temporal resource keeps its paper trail on its own rows. Each version
   then says which action made it, and who did so.
9. Rescord deletes no row that a member removes. It archives the row.
10. A resource with a workflow, such as a task, is not a temporal resource.
    The compiler refuses a resource that is both. ADR 0012 gives the reason.

## 7. Estimate of the resources

This section applies the answers of section 4 and the proposals of sections
5 and 6. Each name is one resource. A different decision changes the count.

### 7.1 The resources in the schema of each organisation

| Area | Resources | Count |
| --- | --- | --- |
| Access | `Member`, `Role`, `MemberRole`, `Grant` | 4 |
| Residents | `Resident`, `ResidentName`, `ResidentStatus`, `ResidentDesexStatus`, `ResidentBreed`, `ResidentColour`, `ResidentTemperament`, `ResidentIdentifier`, `Arrival`, `Departure` | 10 |
| Families and groups | `ParentLink`, `Family`, `FamilyMember`, `Group`, `GroupMember` | 5 |
| Locations | `Location`, `LocationParent`, `Placement` | 3 |
| Journal | `JournalEntry`, `Diagnosis`, `Measurement`, `Procedure`, `Vaccination`, `Prescription`, `Dose`, `Attachment` | 8 |
| Tasks | `Task`, `Routine`, `TaskResident`, `TaskGroup`, `TaskLocation`, `TaskAssignee`, `RoutineResident`, `RoutineGroup`, `RoutineLocation` | 9 |
| Inventory | `Item`, `Lot`, `Supplier`, `StockMovement`, `ReorderLevel` | 5 |
| Lists of the organisation | one for each of the 13 dimensions of section 7.2 | 13 |
| **Total** | | **57** |

### 7.2 The dimensions that an organisation can extend

There are 13: `Species`, `Breed`, `Colour`, `Temperament`, `IdentifierKind`,
`GroupKind`, `LocationKind`, `Condition`, `MeasureKind`, `ProcedureKind`,
`TaskKind`, `ItemCategory`, and `Unit`.

The maintainer decided that each has shared values and local values, and
that a local value is in the schema of its organisation (ADR 0016). Each
dimension thus has two resources:

| Resource | Where it is | What it holds |
| --- | --- | --- |
| The base list | Outside the schemas. All organisations share it. | The shared values. |
| The list of the organisation | In the schema of each organisation. | The local values of that organisation. |

- Each schema holds 13 lists, one for each dimension. They are in the
  count of section 7.1.
- All organisations share 16 resources: the 13 base lists, `Organisation`,
  `User`, and the token of a sign-in.
- The maintainer rejected the other way: one shared resource for each
  dimension, where a local value names the organisation that owns it. That
  way has 13 fewer resources in each schema. It keeps the local values of
  all organisations in one table.

*Proposal.* The list of an organisation holds each value that the
organisation uses. A row of the list names a value of the base list, or it
is a local value with a name of its own. A resident then names one table for
its species, and that table is in the same schema.

### 7.3 The dimensions with a fixed list

*Proposal.* These 10 dimensions are enumerated types, and they are not
resources:

- sex;
- desex status;
- size class;
- coat;
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

With the defaults of rule 7, each of the 57 resources has a version resource.
Only a resource with a workflow is not temporal, and thus adds a table.
`Task` is the only such resource in this estimate.

| | For each organisation |
| --- | --- |
| Resources, with the version resources | 114 |
| Tables | 58 |

AshArchival adds one column to a resource. It adds no resource and no table.

### 7.5 The size of the database

Each table makes about 3 or 4 relations in PostgreSQL: the table, its
indexes, and a store for long text. Thus the 58 tables of one organisation
make about 200 relations. For 50 organisations, the database holds about
2,900 tables and about 10,000 relations. That quantity gives PostgreSQL no
difficulty.

## 8. Open points

1. How does a resident name a value of a dimension, when the value can be in
   the base list or in the list of the organisation? Section 7.2 gives a
   proposal.
2. Which dimensions have a fixed list, and are thus enumerated types?
   Section 7.3 gives a proposal.
3. Which other kinds of task and categories of item are necessary?
4. Can a member of one organisation see a resident that another organisation
   transferred to it?
5. Which resources, other than a resource with a workflow, are not temporal
   resources or keep no paper trail?
6. A placement names a resident or a group. Where does a resident live when
   it has a placement of its own and its group has a different placement?
7. Section 7 does not count the resources that the answers of 15 November
   2026 add, for example the invitation. What is the new estimate?
