# ADR 0057: The photos of a resident in a transfer

Status: accepted (the maintainer asked for it, 27 November 2026). It adds
to ADR 0042, ADR 0043 and ADR 0055.

## Context

A transfer carried the files of the journal entries of its copy, and not
the photo records, the albums or the profile picture (ADR 0055). A
resident arrived at a partner refuge with no photo other than those of its
medical history.

## Decision

- **The photos are a part of the copy, `:photos`**, as the stay and the
  placements are (ADR 0042). The sender ticks it, and the settings of the
  refuge can tick it at first. It is a part and not a fixed piece of the copy
  because the photos are most of the bytes of a transfer.
- **The part holds** each photo of the resident
  (`Rescord.Photos.photos_of/2`: the photo records, and the photos of the
  journal entries) with its caption, its date, its type and its size; the
  albums, each with its name and its photos; and the profile picture. It
  holds no author and no key.
- **A photo has the id of its file.** A photo of a journal entry has the
  id of its attachment, so a copy that holds the entry too holds the file
  once. Each other photo has the id of its record.
- **The thumbnail goes with the photo**, as a file with an id of its own,
  so the refuge that receives the copy shows a grid and makes no image
  itself. The copy states the size of each file, and no record holds the
  size of a thumbnail, so the sender reads the thumbnails when it takes
  the copy. An old photo of the journal has no thumbnail, and the page
  shows the photo in its place.
- **The files travel as the files of the entries do** (ADR 0043): to
  `<refuge>/transfers/<transfer>/<file>` at the refuge that receives, and
  as `files/<id>` in a transfer file. An import checks each photo and each
  thumbnail as it checks each other file: the copy names it, with its size
  and the type that its first bytes give. `Snapshot.clean/1` keeps a photo
  only when its type is an image, and an album and a profile picture only
  when they name photos of the copy.
- **A transfer on one server copies one file at a time**
  (`Rescord.Transfers.Files.copy/3`), so a resident with many photos does
  not hold them all in memory.
- **A transfer file takes 5000 files**, and no longer 1000: a photo is two
  files. The limit of 300 MB stays, and an export now refuses a file past
  it with words that say to leave a part out. Before, the refuge that
  received such a file refused it.

## Consequences

- The refuge that receives reads the photos on the page of the copy, with
  the profile picture and the names of the albums. It has no photo record
  from them, as it has no resident record from the copy (ADR 0042).
- A resident with more than about 300 MB of photos does not fit a transfer
  file. The sender leaves the photos out, or the limit must rise, which
  needs an import that does not hold the file in memory.
- An export still builds the file in memory: about two times the size of
  the photos while it writes.
- The setting of each refuge does not tick the new part: an administrator
  ticks it once in the settings.
