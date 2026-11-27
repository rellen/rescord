# ADR 0055: The photos of a resident

Status: accepted (the maintainer, 26 November 2026).

## Context

A rescue keeps photos of each resident: for its record, for a vet, and for
an adoption. Until now a photo was only a file of a journal entry
(ADR 0041). The maintainer asked for photos with a caption and a date,
grouped into albums, with a profile picture, and for the photos of the
journal to be among them, with a link to their entries.

The maintainer answered four questions:

- A photo can be in several albums of its resident, or in none.
- A photo of the journal is usable as any other photo: in an album, or as
  the profile picture.
- The power `residents` does the work, and a person removes the photos
  that they added; `remove_residents` removes each photo.
- A photo loses its metadata, and gets a thumbnail, through the package
  `image` and libvips. A photo from a phone carries the GPS position where
  somebody took it, which can be the home of a foster carer.

## Decision

- **`Rescord.Photos`** is a domain with four temporal resources: `Photo`,
  `Album`, `AlbumPhoto` (the tie, `archive?: false`, so a photo can go back
  into an album), and `ProfilePhoto` (one for each resident at a time). It
  depends on the residents and the journal; neither of them depends on it.
- **A photo of the journal is a record only when it needs one.**
  `Photos.photos_of/2` gives the photo records of a resident and each photo
  of its journal that is no record yet, with the date of its entry. A
  person who puts such a photo in an album or makes it the profile picture
  calls `adopt`, which makes a `Photo` that names the attachment and the
  same keys in the store: there is no copy. A photo of the journal leaves
  the photos when somebody takes it off its entry; a reader leaves out a
  photo whose attachment is gone. The page offers no removal of it.
- **`Rescord.Images.prepare/1`** makes each photo safe to keep: the type
  from the first bytes (JPEG, PNG, GIF or WebP), no more than 100 million
  pixels, read before libvips decodes the pixels, the turn that EXIF asks
  for, and a new file with no metadata, at most 4096 pixels on a side. The
  thumbnail is a WebP image of at most 480 pixels. An animated GIF keeps its
  frames. The application blocks the loaders that libvips does not trust,
  such as SVG, at its start. The date that the camera recorded is the date of
  the photo when the person gives none, and never a date after today.
- **The photos of the journal get the same treatment**: `StoreAttachment`
  calls `prepare/1` for each photo, and an attachment has `thumbnail_key`.
  An attachment from before this change keeps its file as it was, and has
  no thumbnail; the pages show the photo in its place.
- **The files**: `<organisation id>/photos/<id>` and
  `<organisation id>/thumbnails/<id>`. `RescordWeb.PhotoController` sends a
  photo and a thumbnail as `AttachmentController` sends a file: read with
  the grants of the person, in a sandbox, with no cache.
- **libvips comes with each package.** devenv, CI and the Nix package build
  vix against the libvips of nixpkgs (`VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS`).
  The Docker image and the tarball take the precompiled NIF of vix and its
  libvips for the web formats, which the release holds in the priv of vix:
  a server needs no libvips of its own. Both were 8.18.7 on 26 November
  2026.

## Consequences

- The image is about 36 MB larger, 321 MB in all.
- libvips decodes a photo to turn it: a photo of 48 million pixels from a
  phone takes about 150 MB while Rescord works on it, and one at the limit
  about 300 MB. A server of 2 GB takes a few at a time. ADR 0056 limits how
  many run at once.
- The new dependencies are `image`, `vix` and `color`. A security fix of
  libvips reaches the Docker image and the tarball with a new version of
  vix, and the Nix package with nixpkgs.
- A file of a JPEG, a PNG or a WebP image that Rescord keeps is not the
  file that the person sent: the bytes and the size differ. A test compares
  the stored bytes with `Rescord.StorageFixtures.stored_jpeg/0`.
- A transfer carried the files of the journal, and not the photo records,
  the albums or the profile picture. ADR 0057 adds those as a part of the
  copy.
- The list of the residents shows the profile picture of each resident
  beside its name (27 November 2026). Cinder reads the residents, and their
  pictures are in another domain, which the residents do not depend on. So
  the page reads the profile pictures of the organisation once, when it
  opens (`Photos.all_profile_photos/1`), and finds the picture of each row
  among them. A resident with no picture shows the first letter of its
  name in that place. The picture is decoration there, with an empty `alt`:
  the name is the words of the link. A change of a picture shows when the
  person opens the list again.
- The pages were seen in a browser, in the light and the dark scheme, on a
  wide screen and on a phone (27 November 2026). What that showed is in the
  stylesheet and the markup now. A card of a photo is an `article`: the
  figure, then the form of the photo as one quiet line while it is closed,
  then small buttons in a row. A form that sends files lists each file as
  its name, its progress and its button, and a long name of a file breaks:
  on a phone it made the page wider than the screen, for the journal too.
  A `fieldset` is never wider than its form. Each form of the page has a
  primary button. The form that adds photos and the form of a photo say
  what they refused, since both can be far below the header.
  `RescordWeb.Features.PhotosTest` adds a photo through the browser, and
  holds the width of the page on a phone.
- The export of the data has the four tables, and not the files.
