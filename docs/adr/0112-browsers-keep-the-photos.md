# ADR 0112: Browsers keep the photos for a week

Status: accepted. The maintainer chose this on 28 November 2026, with the
other calls of issue 34.

## Context

Each file that Rescord sent had `Cache-Control: private, no-store`
(ADR 0041): a photo, its thumbnail, a journal file and a receipt. So a
page of photos read each thumbnail again from the server each time it
opened, and a phone on a slow line waited for the same bytes each time.

The bytes behind the address of such a file do not change. A record names
its files once, when it is written, and a new file is a new record with a
new id (ADR 0055). A thumbnail and a display file (ADR 0109) are written
with their record. The one exception is a journal photo that Rescord 0.1.0
kept as it was sent: the job of the images (ADR 0109) writes its file again
with no metadata, under the same key, and gives it a thumbnail at the same
time. Until then it has no thumbnail.

A copy in a browser outlives the grant that let the person read it: when a
member leaves the organisation, or a photo is removed, the browsers that
kept it still have it. On a computer that several people share, the next
person can find the photos of the last one in the cache.

## Decision

1. **A file whose bytes never change gets
   `Cache-Control: private, max-age=604800, immutable`**
   (`RescordWeb.FileCache.kept/0`): a photo, its thumbnail and its display
   file, a journal file with its thumbnail and display file, and a
   receipt. `private` keeps it out of each shared cache, so only the
   browser of the person keeps it. A week is long enough for the pages
   that a person opens each day, and short enough that a copy does not
   stay for months. `immutable` tells the browser not to ask again when
   the person reloads the page.
2. **A journal photo that the job has not cleaned keeps `no-store`**
   (`RescordWeb.FileCache.stable?/1`): an image with no thumbnail key is
   such a photo, both on the attachment and on its photo record. Once the
   job has cleaned it, it has a thumbnail, and its next answer is kept.
   No browser kept the old bytes, because they were sent with `no-store`.
3. **Everything else keeps `private, no-store`**: the files of a transfer
   (a copy from 0.1.0 can hold an uncleaned photo, and a transfer is read
   rarely), the reports, the exports and the pages.
4. **The sign-out sends `Clear-Site-Data: "cache"`**
   (`RescordWeb.UserAuth.sign_out/1`), which asks the browser to drop
   what it kept of the server. It clears the cache of the server alone,
   and not its cookies or its storage, so the sign-out works as before.
5. **The read with the grants of the person still decides who gets a
   file.** A browser that has no copy asks the server, and the server
   answers as before (ADR 0041). The cache changes nothing for a person
   who never had the file.

## Consequences

- A page of photos opens with no read of the thumbnails that the browser
  has, and the server sends fewer bytes.
- A person who leaves, or whose role loses the photos, can still see in
  their browser, for up to a week, a photo that they opened before. They
  saw it already; the cache adds no person who can see it.
- A browser that does not know `Clear-Site-Data`, and a session that ends
  with no sign-out (it times out, or the person closes the browser), keep
  the photos until the week is over. A shared computer should use a
  private window, as for any site.
- An operator who must take a photo out of every browser at once (for a
  photo sent by mistake) cannot: removing it stops each new read, and the
  copies end within a week.
