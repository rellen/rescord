# ADR 0113: Safer uploads: a watch on libvips, a virus scan of PDFs, clean photos in a transfer

Status: accepted. The maintainer chose the nine calls of issue 37 on
28 November 2026. The watch on libvips and the scan of PDFs are
built; the transfers follow, and this record grows with them.

## Context

A review of the uploads (issue 37) found what is in place: the type comes
from the first bytes, a photo is written again from its pixels
(ADR 0055), a name never reaches a path, a file goes out in a sandbox with
`nosniff`, the store is private, and a transfer is checked before it is
decrypted and decompressed (ADR 0043). It found four gaps:

1. a PDF is kept and sent as the person sent it;
2. a photo of an imported transfer keeps the bytes of the other server;
3. nothing watches libvips, which reads each photo inside the BEAM;
4. the files come from the domain of the application.

## Decision

### libvips

libvips and its decoders (libjpeg, libpng, libwebp, giflib) run in the
BEAM, as the NIF of vix. The check of advisories in CI (`mix hex.audit`,
ADR 0048) covers the Hex packages, not the C libraries in them. The
Docker image and the tarball take the libvips that a release of vix
builds (`PRECOMPILED_NIF_AND_LIBVIPS`), so a fix of libvips reaches them
only with a new version of vix. The Nix package links the libvips of
nixpkgs, which an update of `flake.lock` brings.

1. **A weekly workflow, `libvips.yml`, reports a newer `vix` or `image`.**
   It runs `scripts/check-libvips.sh` each Monday, which compares
   `platform/mix.lock` with the newest stable version on Hex and fails
   when Hex has a newer one. It reports only: no push starts it, and it
   needs no Elixir. Its name says libvips, so a red run reads as a fix of
   security that may wait.
2. **`bin/check` names the version of libvips that runs**
   (`Rescord.Images.libvips_version/0`), and so does the colophon for a
   person who is signed in. A visitor does not see it, for the reason that
   the footer shows the version of Rescord only to a person who is signed
   in: a version helps a person who looks for a known fault.
3. **A new version of vix that brings a new libvips gets an entry under
   "Security" in `CHANGELOG.md`.**
4. **No decode in a process of its own.** It would keep a fault of a
   decoder away from the application, at the cost of a port, a protocol
   and the memory of a second program. The limits of ADR 0056 (the pixels
   read before the decode, two decodes at a time) stay the guard.

### A virus scan of PDFs

1. **The setting is an Ash resource, not the environment** (ADR 0068):
   `Rescord.Storage.Scan.Settings`, one row of the server in the domain
   `Rescord.Storage.Scan`, which a root user sets at `/root/scan`: on or
   off, and the address of clamd, `host:port` or the absolute path of a
   Unix socket. clamd takes no password, so the row holds no secret. Only a
   root user reads or changes it, and the policy sweep (ADR 0064) holds
   that. With no row, or with the scan off, nothing is scanned.
2. **"Test" sends `PING`** to the address in the form, saved or not, so a
   root user sees that clamd answers before turning the scan on.
3. **Each PDF of a journal file or of a receipt goes to clamd** before its
   record is written (`Rescord.Storage.Scan.check/1`, called by the change
   that stores the file). A photo does not: it is written again from its
   pixels (ADR 0055), so the bytes that were sent are not what Rescord
   keeps. The PDFs of an imported transfer are scanned by the job of the
   transfers, below.
4. **No library.** `Rescord.Storage.Scan.Clamd` speaks `zPING` and
   `zINSTREAM` over `:gen_tcp`, in chunks of 256 KiB, with 5 seconds for
   the connection and 30 for the answer.
5. **A find is refused** with the reason `:infected` of `RefusedFile`, and
   the log has a warning with the name that clamd gave and no name of the
   file. **With the scan on, a clamd that does not answer refuses the
   file** with the reason `:unscanned`: a root user who turned the scan on
   wants no PDF that was not scanned.
6. `bin/check` has a line `scan`, and the metric `rescord_scan_count`
   counts the scans by result: `clean`, `found`, `fault`.
7. **clamd is not in the image**: its signatures take a few GB of memory,
   more than a small server has. `docs/self-hosting.md` shows how to run
   it beside Rescord.
8. The PDFs in the store now are not scanned. A PDF opens in the browser
   as now: the viewer of a browser runs in a sandbox, and a download would
   open it in a program of the desktop, which is often less guarded.

The domain is `Rescord.Storage.Scan`, and not a module of the core: a
resource needs a domain, and the core has none. The changes of the journal
and of the expenses call it, so those two domains depend on it.

### The photos of an imported transfer (to follow)

A job writes each photo of a copy again with no metadata after the
import, and the files of the copy are held until it ends
(`files_checked_at`). The transfers that are there count as checked.

### A domain of its own for the files (later)

Designed in issue 37 and not built: a second host name with a short
signed token in place of the session cookie, a second guard behind the
`sandbox`.

## Consequences

- An operator learns of a new vix within a week, and can compare the
  libvips that runs with an advisory.
- The first run of the workflow can be red: on 28 November 2026, Hex has
  `image` 0.75.0, and `mix.lock` has 0.74.0.
- A fix of libvips that no new vix brings is not seen by the workflow.
