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
| resident | An animal that an organisation has in its care. |
| family | A named set of residents that came together or were born together, for example a litter. |
| parent link | A record that one resident is the mother or the father of another resident. |
| group | A set of residents that the organisation manages together, and that is not a family. |
| location | A place where a resident lives, or where the organisation keeps a lot. |
| clinical entry | One record in the medical history of a resident. |
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
6. medical histories;
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
| Which facts about a resident need a history? | The name, the status, the desex status, and the weight and other measurements. |
| Is the departure of a resident in scope? | Yes: death, release, and transfer to another organisation. |
| What does a family record? | Both the parent links and a named set of residents. |
| Can one user work for more than one organisation? | Yes. |
| How does a location contain a location? | Each organisation defines its own kinds, and a location can be inside any other location. |
| Which other dimensions does a resident have? | Identifiers, size class, coat, temperament, and desex status. |
| What does a completed `medicate` task record? | The task, and a clinical entry for the dose. It records no stock movement. |
| How does Rescord track the inventory? | By lot, with an expiry date, and by location. |
| Who writes a clinical entry? | A member only. |
| Which tools keep the history? | The temporal resources of Ash, AshPaperTrail, and AshArchival (ADR 0012). |

## 5. The root entities

### 5.1 Users

A user is a person who can sign in to Rescord. All organisations share the
users. A member connects one user to one organisation.

*Proposal.* A member has one or more roles, and a role has grants. The
section "Policies and roles" of `docs/architecture.md` describes the grants.

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
- The weight is a measurement in the medical history, so it has a history
  already.
- An arrival records how and when a resident came to the organisation. A
  departure records how and when a resident left.
- The age is not a dimension. Rescord calculates the age from the date of
  birth.

*Proposal.* The arrival kinds are: surrender by an owner, stray, seizure by
an authority, birth in care, and transfer from another organisation. The
departure kinds are: death, release, and transfer to another organisation.

*Proposal.* A resident is in care when it has an arrival and no departure.
Rescord calculates that fact. The status is for the other states, for example
quarantine.

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
- A placement records that a resident lives in a location from one date to
  another date.

*Proposal.* A location cannot contain itself, directly or through other
locations. Rescord rejects such a tie.

### 5.6 Medical histories

The medical history of a resident is the list of its clinical entries. A
member writes each clinical entry.

*Proposal.* A clinical entry has one of these kinds:

- examination;
- diagnosis of a condition;
- measurement, for example the weight;
- procedure;
- vaccination;
- prescription of a medication;
- dose of a medication that a member gave.

### 5.7 Tasks

A task is one piece of work. The maintainer gave these kinds of task, and
there can be many more:

- feed;
- medicate;
- clean;
- groom.

When a member completes a `medicate` task, Rescord also writes a clinical
entry for the dose. It does not change the inventory.

*Proposal.* A task has one or more subjects. A subject is a resident, a
group, or a location. A routine is a task that repeats. AshWorkflow holds the
states of a task.

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

## 6. Design rules

The maintainer asked for a design in 5NF and 6NF.

1. Each table is in 5NF.
2. An attribute gets a table of its own, in 6NF, when the organisation needs
   its history. Such a table is a temporal resource: it holds the key, the
   period for which the value is valid, and the value. Section 4 names the
   attributes.
3. A dimension that an organisation can extend is a resource. It has shared
   values and local values.
4. *Proposal.* A dimension with a fixed list of values is an enumerated type,
   and it is not a resource.
5. A relation of many to many is a tie.
6. Rescord stores a fact one time and calculates the other values. The age,
   the stock level, and the relatives of a resident are examples.
7. A temporal resource keeps its paper trail on its own rows. Each version
   then says which action made it, and who did so.
8. Rescord deletes no row that a member removes. It archives the row.
9. A resource with a workflow, such as a task, is not a temporal resource.
   ADR 0012 gives the reason.

*Proposal.* These resources are temporal resources: `ResidentName`,
`ResidentStatus`, `ResidentDesexStatus`, `Placement`, and `GroupMember`. Each
states a fact about a resident that is valid for a period.

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
| Medical histories | `ClinicalEntry`, `Diagnosis`, `Measurement`, `Procedure`, `Vaccination`, `Prescription`, `Dose`, `Attachment` | 8 |
| Tasks | `Task`, `Routine`, `TaskResident`, `TaskGroup`, `TaskLocation`, `TaskAssignee`, `RoutineResident`, `RoutineGroup`, `RoutineLocation` | 9 |
| Inventory | `Item`, `Lot`, `Supplier`, `StockMovement`, `ReorderLevel` | 5 |
| **Total** | | **44** |

### 7.2 The dimensions that an organisation can extend

There are 13: `Species`, `Breed`, `Colour`, `Temperament`, `IdentifierKind`,
`GroupKind`, `LocationKind`, `Condition`, `MeasureKind`, `ProcedureKind`,
`TaskKind`, `ItemCategory`, and `Unit`.

The maintainer decided that each has shared values and local values. The way
to store them is not decided. There are two ways:

| Way to store a dimension | Resources for each organisation | Resources that all organisations share |
| --- | --- | --- |
| One shared resource for each dimension. A local value names the organisation that owns it. | 44 | 16 |
| One shared resource for the base list, and one resource in each schema for the list of the organisation. | 57 | 16 |

The 16 shared resources are the 13 dimensions, `Organisation`, `User`, and
the token of a sign-in.

*Proposal.* Use the first way. It has fewer resources, and a resident names
one table for its species. The second way keeps each local value inside the
schema of its organisation, at the cost of 13 more resources in each schema.

### 7.3 The dimensions with a fixed list

*Proposal.* These 10 dimensions are enumerated types, and they are not
resources:

- sex;
- desex status;
- size class;
- coat;
- kin role;
- kind of clinical entry;
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

The count depends on which resources keep a paper trail:

| Paper trail on | Resources for each organisation | Tables for each organisation |
| --- | --- | --- |
| the 5 temporal resources only | 49 | 44 |
| each of the 44 resources | 88 | 83 |

AshArchival adds one column to a resource. It adds no resource and no table.

### 7.5 The size of the database

Each table makes about 3 or 4 relations in PostgreSQL: the table, its
indexes, and a store for long text. Thus the 44 to 83 tables of one
organisation make about 150 to 290 relations. For 50 organisations, the
database holds 2,200 to 4,150 tables, and no more than about 14,500
relations. That quantity gives PostgreSQL no difficulty.

## 8. Open points

1. How does Rescord store a dimension with shared values and local values?
   Section 7.2 gives two ways.
2. Which dimensions have a fixed list, and are thus enumerated types?
   Section 7.3 gives a proposal.
3. Which values does the status of a resident have?
4. Which other kinds of task and categories of item are necessary?
5. How does a routine state when it repeats?
6. Does a reorder level apply to an item in the whole organisation, or to an
   item in one location?
7. Can a member of one organisation see a resident that another organisation
   transferred to it?
8. Which resources are temporal resources? Section 6 gives a proposal.
9. Which resources keep a paper trail? Section 7.4 gives the two ends of the
   range.
10. Does a clinical entry change after a member writes it, or does a
    correction make a new clinical entry?
