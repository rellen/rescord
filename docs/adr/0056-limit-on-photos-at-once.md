# ADR 0056: A limit on the photos that libvips works on at once

Status: accepted (the maintainer asked for the limit on 27 November 2026;
the numbers are a first choice).

## Context

libvips decodes a photo to turn it (ADR 0055): a photo of 48 million pixels
from a phone takes about 150 MB while Rescord works on it, and one at the
limit of 100 million pixels about 300 MB. Nothing limited how many photos
went through libvips at the same time. A server of 2 GB, which is what
`docs/self-hosting.md` asks for, also runs the database in most
installations. Ten large photos at once could take more than 1 GB.

The photos of one form already go one after the other: the page adds each
photo in its own process, in turn. The photos of two people, of two tabs,
or of the journal and the photos page do not.

An image of libvips is a resource of the NIF of vix. Its memory is free
again when the process that made it collects its garbage or ends, and not
when `Rescord.Images.prepare/1` returns. A page that adds ten photos in
turn can hold what libvips kept for the first while it works on the last.

## Decision

- **`Rescord.Images.Limit`** is a server with a number of slots.
  `Rescord.Images.prepare/1` runs the work of libvips through
  `Limit.run/1`, so the photos of a resident and the photos of the journal
  share the slots. Each node has its own slots.
- **Work that finds no slot waits**, and the slot goes to the work that has
  waited longest. A person who sends ten photos gets ten photos, and not an
  error for eight of them.
- **A wait has an end**: after 30 seconds the photo is refused with "waited
  too long behind other photos. Try again in a minute", and Rescord logs a
  warning that names the setting. A page does not hang for longer.
- **The work runs in a process of its own**, which holds the slot until it
  is gone. `run/1` returns after that. So what libvips holds for a photo is
  free before the next photo starts, and a slot comes back when its work
  fails or its page closes. The process is linked to its caller: a failure
  of libvips stops the caller as before.
- **Two slots by default**, which is 300 MB for two photos of a phone and
  600 MB for two photos at the limit. `RESCORD_PHOTO_SLOTS` sets the number
  on a server with more memory, from 1 to 64.
- The check of the type from the first bytes stays outside the limit: a
  file that is not a photo is refused with no wait.

## Consequences

- The memory that libvips takes for the pixels has a bound: the slots
  times the memory of one photo. The bytes that people sent are outside
  the bound: each photo that waits is in memory, at most 20 MB each.
- A page waits while its photo waits. With two slots and a few seconds for
  each large photo, some ten photos can be in front of a photo before its
  30 seconds end.
- libvips keeps a cache of its last operations, of 100 MB at most by its
  default. The limit does not change that.
- The limit is in the memory of one node. Rescord runs as one node today.
- The memory of a photo was not measured again for this decision: the
  numbers are those of ADR 0055.
