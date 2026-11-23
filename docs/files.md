# Files

Ported from the iPad's `FilesViews.swift`, `Files.swift` and `TafsCloud+Files.swift` (tafs docs/files.md): what the
account's tafs delivered in their runs, kept 30 days from the run and seen by everyone on the account. tafs cloud's
own switch decides: with Files off (404) there are none.

## Where

- **Account › Files**, after Connect apps in People & apps, as the iPad's row: the account's files.
- **A taf's Files**, first on its header line ("Files · Version 5 · live", the owner's 19 Nov test), for every taf
  tafs cloud runs, with how many it has kept now; it shows with none yet too. It opens the taf's files over its page.
  The header line now shows for anyone with a Files entry; its version and who it's shared with stay the manager's.

## The list and the open file (`FilesView`, `FileDetailView`, `FilesModel`)

As the iPad's full width: the list and the open file side by side, the first file open until another is clicked.
- **Read** (`GET /v1/files`, then `?after=` while tafs cloud sends `next`, at most 10 pages), newest first. A file
  that doesn't read is left out, never the page. A failed read says Files couldn't be read, with Try again.
- **The account's:** All (by the run's day in the account's zone), By taf, By run, and a chip per taf with files.
  **A taf's:** by run. Under the list, tafs cloud's rule: kept 30 days from its run, for everyone on the account.
- **A row:** its type as a badge (its extension, else its media type's last part, upper case), its name, the taf
  that made it and its size, and when it goes (today, tomorrow, in so many days), in amber.
- **The open file:** tafs cloud's cleaned start (`GET /v1/files/{id}`), drawn as plain monospaced text, never Markdown,
  HTML or a viewer of the bytes, with "Only the start is shown" when there's more. For a text type (CSV, MD, TXT,
  JSON) tafs cloud couldn't reach, the couldn't-read line; for any other type, or one it answered without a start, no
  preview. Then Made by, In the run, Type, Size, Who sees it (everyone on this account) and Goes away.
- **Download:** where to, as the person picks (a save panel, named as the file is); then `GET /v1/files/{id}/download`
  for a URL that lasts a minute, and its bytes, written straight there and nowhere else. "Saved to this device", or why
  not. **The URL is checked** as Linux checks it: https only, with no user or password in it. Its bytes are read with no
  token, no cookie, no cache and **no redirect** (a 3xx fails), so the session never goes beyond KIFF's and tafs cloud's
  hosts.
- **Delete now**, at the end, behind a confirm ("Delete “{name}” now?", it goes for everyone right away and can't be
  undone): `DELETE /v1/files/{id}`; the file leaves the list only once tafs cloud has deleted it.

## Names and text (`FileText`)

As the iPad's (qa-kiff's musts): a name is what follows the last `/` or `\`, with control and direction characters
(U+202A–U+202E, U+2066–U+2069, U+200E, U+200F, U+061C) taken out; nothing, "." or ".." is the file's id. A preview
keeps its lines and tabs and drops every other control or direction character, even if tafs cloud's own cleaning
let one through.

## Not here yet

- **Share** (the iPad's share sheet with the file itself).
- **A system preview of a file with no text start** (the iPad's Quick Look of the bytes on the device): this Mac reads
  a file's bytes only for Download, as Windows keeps copies temporary and never launches them.
- **The chat's file chips** (`ChatFileChips`), drawn once tafs cloud says which run a message is.
