# ADR 0043: Transfers between servers

Status: accepted (the answers are from the maintainer, 19 November 2026).
It adds to ADR 0042.

## Context

Most refuges will run Rescord on servers of their own, so a partner is
often on another server, and ADR 0042's transfer cannot reach it. The
maintainer answered:

- An import is a received transfer: a copy that waits for an answer.
- A file is signed by the refuge that sends it, and encrypted for the
  refuge that receives it.
- A refuge imports a file only from a partner that it recorded.
- A file carries the photos and the PDFs of the entries of its copy.

## Decision

- **Each refuge has two key pairs**, made the first time that it needs
  them: Ed25519 to sign, and X25519 to receive. `:crypto` of OTP does both,
  so there is no new dependency. The private keys are in the table
  `refuge_keys`, encrypted with AES-256-GCM under the secret of the server
  (`RESCORD_KEY_SECRET` in production, 32 bytes at least).
- **A partner card** is one line of text with the id, the name and the two
  public keys of a refuge. Two administrators exchange cards, record the
  card of the other (`RemotePartner`), and read the fingerprint, 32 hex
  digits, to each other before the first file. The card holds no secret.
- **The file** (`.rescord`) is a frame of three parts, and not a zip, so
  that nothing decompresses before the check:
  - a JSON header, which says who sends it and to whom;
  - the Ed25519 signature of the exact bytes of the header;
  - the payload: a zip of the copy and its files, encrypted with
    AES-256-GCM. The key comes from X25519 between a key pair of the file
    alone and the key of the receiver, through HMAC-SHA256 with both public
    keys. The header, less the hash, is the additional data, and the header
    holds the SHA-256 of the payload, so the signature covers both.
- **An import checks, in order**: the frame; that the file is for this
  refuge; that it comes from a partner that this refuge recorded and has
  not ended; the signature with the key of that partner; the hash; the
  decryption; the names and sizes of the zip before it decompresses; that
  the facts inside match the header; the copy, which
  `Snapshot.clean/1` rebuilds with the keys and types that Rescord knows;
  and that the files are those that the copy names, each with its size and
  a type that its first bytes give. A file imports one time: the id of the
  export is unique for each refuge that receives.
- **An export** keeps a record with the state `exported`, and no file. The
  file goes out as a download from `RescordWeb.TransferFileController`,
  because a page of LiveView cannot send a file.
- **The files of a copy.** The refuge that receives a transfer keeps its
  own copy of each file under `<refuge>/transfers/<transfer>/<file>`. A
  transfer on one server now copies the files too, so both kinds of copy
  have them.
- The power `:transfers` covers the record of a card, the end of a remote
  partnership, the export and the import.

## Consequences

- A refuge that loses `RESCORD_KEY_SECRET` loses its keys. It makes new
  ones only when an operator removes the old row, and then each partner
  records its new card. Keep the secret with the backups.
- Nobody checks a fingerprint for the administrators: a card that an
  attacker swaps on its way passes until the two read the fingerprint to
  each other. The page says so.
- The receiver decrypts in memory, and an import takes a file of 300 MB at
  most. Only a person with the power imports, and only after the signature
  of a recorded partner, does the zip decompress.
- The header is not secret: it names the two refuges and the id of the
  export, but nothing of the resident.
- A file that the receiver never imports leaves only the record of the
  export at the sender. Nothing tells the sender of an answer on the other
  server.
