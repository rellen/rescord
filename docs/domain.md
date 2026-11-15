# The domain of Rescord

This document follows ASD-STE100 Simplified Technical English.

The maintainer gave the scope of this document on 15 November 2026. A
paragraph that starts with the word *Proposal* is an idea that the maintainer
has not agreed yet. Section 6 holds estimates, not measurements.

## 1. Purpose

Rescord is a management system for an animal rescue or an animal refuge. An
organisation uses Rescord to record its residents, the care that they get,
and its supplies.

## 2. Terms

| Term | Definition |
| --- | --- |
| organisation | A rescue or a refuge that uses Rescord. One organisation is one tenant. |
| user | A person who can sign in to Rescord. |
| resident | An animal that an organisation has in its care. |
| family | A set of residents that are relatives, for example a mother and her young. |
| group | A set of residents that the organisation manages together, and that is not a family. |
| location | A place where a resident lives, or where the organisation keeps an item. |
| clinical entry | One record in the medical history of a resident. |
| task | One piece of work that a person does for a resident, a group, or a location. |
| item | A type of supply that the organisation keeps, for example one brand of dry food. |
| entity | An object that has an identity of its own, for example a resident. |
| dimension | A list of permitted values that describes an entity. The species is an example. |
| tie | A table that connects two or more entities. |
| resource | An Ash resource. One resource maps to one table of the database. |
| 5NF | Fifth normal form. The keys of a table in this form imply each way to divide the table with no loss of data. |
| 6NF | Sixth normal form. A table in this form holds a key and no more than one other attribute. |

## 3. Scope

These root entities are in scope:

1. users;
2. residents;
3. families of residents;
4. groups of residents;
5. locations of residents;
6. medical histories;
7. tasks;
8. inventory.

These subjects are out of scope for now:

- adoption;
- foster care.

## 4. The root entities

### 4.1 Users

A user is a person who can sign in to Rescord.

*Proposal.* A member is a user who belongs to one organisation. A member has
one or more roles, and a role has grants. The section "Policies and roles" of
`docs/architecture.md` describes the grants.

### 4.2 Residents

A resident is an animal in the care of an organisation. A resident has these
dimensions:

- species;
- sex;
- colour;
- breed.

*Proposal.* A resident can also have these dimensions:

| Dimension | Example values |
| --- | --- |
| desex status | entire, desexed, not known |
| coat | short, long, wire, no coat |
| size class | small, medium, large |
| identifier kind | microchip, ear tag, leg band, tattoo |
| arrival kind | surrender by an owner, stray, seizure by an authority, birth in care, transfer from another organisation |
| departure kind | death, release, transfer to another organisation |

- A resident can have more than one breed and more than one colour. Each of
  the two is a tie, and not a column of the resident.
- A resident can have more than one identifier, each of one identifier kind.
- The age is not a dimension. Rescord calculates the age from the date of
  birth.

### 4.3 Families of residents

A family records which residents are relatives.

*Proposal.* Each member of a family has a kin role: mother, father, or young.

### 4.4 Groups of residents

A group is a set of residents that is not a family. A bonded pair, a herd, a
flock, and a set of residents in quarantine are examples.

*Proposal.* A group has a group kind. The membership of a resident in a group
has a start date and an end date.

### 4.5 Locations of residents

A location can be one of these elements, from the smallest to the largest:

1. unit;
2. bay;
3. level;
4. room;
5. `building`;
6. campus.

The maintainer has not decided which elements exist, or which element can
contain which.

*Proposal.* Rescord holds one entity, the location, and one dimension, the
location kind. A tie records which location contains a location. Each
organisation then makes its own hierarchy from data, and a change to the
hierarchy needs no migration. A placement records that a resident lives in a
location from one date to another date.

### 4.6 Medical histories

The medical history of a resident is the list of its clinical entries.

*Proposal.* A clinical entry has one of these kinds:

- examination;
- diagnosis of a condition;
- measurement, for example the weight;
- procedure;
- vaccination;
- prescription of a medication.

### 4.7 Tasks

A task is one piece of work. The maintainer gave these kinds of task, and
there can be many more:

- feed;
- medicate;
- clean;
- groom.

*Proposal.* A task has one or more subjects. A subject is a resident, a
group, or a location. A routine is a task that repeats. AshWorkflow holds the
states of a task.

### 4.8 Inventory

The inventory is the set of supplies of an organisation. The maintainer gave
these categories of item, and there can be many more:

- food;
- `bedding`;
- medication;
- `cleaning product`;
- `cleaning tool`.

*Proposal.* A lot is one delivery of an item, and it can have an expiry date.
A stock movement records that a quantity of an item came in or went out.
Rescord does not store the stock level. It calculates the level from the
stock movements. A task that uses an item records a stock movement.

## 5. Design rules

The maintainer asked for a design in 5NF and 6NF.

*Proposal.* These rules apply the two forms:

1. Each table is in 5NF.
2. An attribute gets a table of its own, in 6NF, when the organisation needs
   the history of that attribute. Such a table holds the key, the time from
   which the value applies, and the value.
3. A dimension is a resource when an organisation can change its values. A
   dimension with a fixed list of values is an enumerated type, and it is
   not a resource.
4. A relation of many to many is a tie.
5. Rescord stores a fact one time and calculates the other values. The age
   and the stock level are examples.

## 6. Estimate of the resources for each organisation

This section applies the proposals of sections 4 and 5. Each name is one
resource. A different decision in section 4 changes the count.

| Area | Entities | Dimensions | Ties and events | Total |
| --- | --- | --- | --- | --- |
| Access | `Member`, `Role` | none | `MemberRole`, `Grant` | 4 |
| Residents | `Resident` | `Species`, `Breed`, `Sex`, `Colour`, `DesexStatus`, `Coat`, `SizeClass`, `IdentifierKind`, `ArrivalKind`, `DepartureKind` | `ResidentBreed`, `ResidentColour`, `ResidentIdentifier`, `Arrival`, `Departure` | 16 |
| Families and groups | `Family`, `Group` | `KinRole`, `GroupKind` | `FamilyMember`, `GroupMember` | 6 |
| Locations | `Location` | `LocationKind` | `LocationParent`, `Placement` | 4 |
| Medical histories | `ClinicalEntry` | `EntryKind`, `Condition`, `MeasureKind`, `ProcedureKind`, `Route` | `Diagnosis`, `Measurement`, `Procedure`, `Vaccination`, `Prescription`, `Attachment` | 12 |
| Tasks | `Task`, `Routine` | `TaskKind` | `TaskResident`, `TaskGroup`, `TaskLocation`, `TaskAssignee`, `RoutineResident`, `RoutineGroup`, `RoutineLocation` | 10 |
| Inventory | `Item`, `Lot`, `Supplier` | `ItemCategory`, `Unit`, `MovementReason` | `StockMovement`, `ReorderLevel` | 8 |
| **Total** | **12** | **22** | **26** | **60** |

All organisations share three more resources: `Organisation`, `User`, and the
token of a sign-in.

The count changes with the design:

| Design | Resources for each organisation |
| --- | --- |
| 5NF, and each dimension is a resource | about 60 |
| 5NF, and each fixed dimension is an enumerated type | about 50 |
| 5NF, and 6NF for about 10 attributes that need a history | about 70 |
| 6NF for each attribute | about 120 |

- The second row assumes that about 10 of the 22 dimensions have a fixed
  list of values. `Sex` and `KinRole` are examples.
- The last row adds a table for each attribute: about 40 attributes of
  entities, and about 20 attributes of ties.
- A design in 6NF keeps its own history. It then needs no version resource
  from AshPaperTrail, which adds one resource for each resource that it
  follows.

Each resource makes about 3 or 4 relations in PostgreSQL: the table, its
indexes, and a store for long text. Thus 60 resources make about 200
relations, and 120 resources make about 400 relations.

## 7. The effect on tenancy

The maintainer has not chosen between one schema for each organisation and
one shared schema with an organisation column.

- With one schema for each organisation, 1,000 organisations of 60 resources
  make 60,000 tables and about 200,000 relations.
- AshPostgres migrates the schemas one after the other, so the time of a
  migration grows with the number of organisations.
- All organisations can share a dimension that has the same values for each
  of them. If all 22 dimensions are such dimensions, each organisation has
  about 38 resources.

## 8. Open points

1. Which of the proposed dimensions of a resident are necessary, and which
   others are necessary?
2. Does each organisation keep its own values of a dimension, or do all
   organisations share them?
3. Which kinds of location exist, and which kind can contain which?
4. Is a family a set of relatives, or a record of each parent of a resident?
5. Can one user belong to more than one organisation?
6. Which attributes need a history, and thus a table in 6NF?
7. Which other kinds of task and categories of item are necessary?
8. Is the departure of a resident in scope, while adoption is out of scope?
9. How many organisations will use Rescord: tens, hundreds, or thousands?
   The answer decides the tenancy.
