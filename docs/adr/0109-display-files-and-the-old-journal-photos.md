# ADR 0109: Display files, and the journal photos of 0.1.0

Status: accepted. The design is issue 34, and the maintainer chose each of
its ten points as written on 28 November 2026. It extends ADR 0055 (the
photos of a resident) and ADR 0091 (the file check), and uses ADR 0056
(the slots of libvips).

## Context

`Rescord.Images.prepare/1` makes each photo safe to keep since 26
November 2026 (ADR 0055): no metadata, at most 4096 pixels on a side, and
a thumbnail of 480 pixels. A read of the code on 28 November 2026 found
three gaps of the photos (a fourth, the cache of a browser, comes in a
later step of issue 34):

- Journal attachments came on 19 November 2026 and were in the release
  0.1.0 (20 November 2026), before `prepare/1`. A server that ran 0.1.0
  keeps each journal photo from then as it was sent, with its EXIF block
  and the GPS position, and sends it as it is. A copy of a transfer made
  from such a photo holds the same bytes.
- A HEIC photo was refused with words that did not say what to do. This
  is on main already (`Rescord.Images.heif?/1`, `RescordWeb.UploadWords`).
- A phone that opens a photo reads the file of up to 4096 pixels, often a
  few megabytes.

## Decision 1: a display file

`prepare/1` makes a third file of each photo that is not a GIF: a WebP
image of at most 1600 pixels on its longest side (`display_side/0`), at
quality 80, from the photo that it turned and sized already, so libvips
decodes nothing more. `Photo` and `Attachment` hold its key in
`display_key`, `<organisation id>/displays/<id>`. A receipt makes none: it
opens its full file, so that small print stays readable.

`/o/<short name>/photos/<id>/display` and
`/o/<short name>/attachments/<id>/display` send it as the thumbnail is
sent. A link of a photo card, of the profile picture and of a journal
photo opens the display file when there is one; the card has a link
"Full size" to the photo. The cage card prints the profile picture from the
display file; the record of a resident keeps the thumbnails for its 24
photos. A transfer does not carry the display file: the copy stays as it
was, and the receiver opens the full file. `Rescord.Storage.Named` names
`display_key`, so `bin/check-files` counts the display files.

## Decision 2: one job completes the files

`Rescord.Images.Workers.Complete` starts each hour (cron at :53), in the
queue `images` with one job at a time, and puts a job for each
organisation. A job takes 50 rows, the attachments first and then the
photo records, in the order of their ids, and puts the job of the next
batch with the last id. Each photo goes through `Rescord.Images.Limit`,
with the uploads; a photo that waits too long ends the batch, and the job
snoozes for a minute. The worker is unique for each organisation while it
waits, so an hourly start does not add a second chain to one that runs.

- **A journal photo with no thumbnail** is a photo of 0.1.0. The job runs
  it through `prepare/1`, puts the clean photo under the same key, and its
  thumbnail and display file under the keys that an upload uses now. Each
  copy of it in a transfer to an organisation of this server
  (`Rescord.Transfers.file_copies/2`) that the store has gets the clean
  bytes, and the copy gets their size (`Rescord.Transfers.put_file_size/3`).
  The original leaves the store.
- **A photo with no display file** gets one, from `Rescord.Images.display/1`.
- **A photo that it cannot make** stays as it is. The batch goes past it,
  the next hourly start tries it again, and each batch logs one warning
  with the count. `bin/check-files` prints the number of journal photos
  that still carry their metadata, when there is one.

The job updates the tables, with no actor and no action: `size`,
`thumbnail_key` and `display_key` on the attachment, and on each version
row of each photo record that names it. The keys and the size are facts of
the file, and each version of a photo names the same files, so the job
makes no new version and no entry in the paper trail. No action of a
person writes these columns, and the policy sweep has no new action.

A fault after a put leaves a file under a new key that no record names,
which `bin/check-files` reports as a leftover, as for an upload. The put of
the disk store writes a part and renames it, and S3 replaces an object
whole, so a reader gets the old photo or the clean one.

## Consequences

- A migration of each organisation adds the empty column `display_key` to
  `journal_attachments` and `photos`. An older version ignores it.
- The store grows by about a tenth of the size of the photos. The fixtures
  are one colour, so the tests cannot measure it; a photo of a phone was
  not tried.
- A server with many photos uses more CPU for some hours after the
  upgrade, at most two decodes at a time.
- The job cannot clean a backup, an older object version of a bucket with
  versioning, or an export of a transfer. The upgrade notes say so.
- A journal photo of 0.1.0 in a copy that another server imported is not
  reached: issue 37 writes the photos of an import again.
- Not tested: the snooze when libvips is busy, which needs the two slots
  held by other work.
