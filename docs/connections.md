# Connect apps

The account's own connections, then the catalog of apps a taf can use. **This screen lists.**
An app is connected through Coach, where its Card is approved with it, so the row's Connect
and Sign in again, and "Not listed? Ask Coach", open Coach. This screen sends nothing but
`GET`. Once the app is connected, its receipt shows over Coach (below, "The receipt").

## What is read (`Apps`, `CloudClient.apps(_:cursor:)`)

`GET /v1/connect/apps?q=&cursor=` on tafs cloud.

| Drawn | From |
|---|---|
| The row's name | `name` (an older tafs cloud's `title`). Never `vendor`, which is a key. |
| What this entry of the app is | `subtitle` |
| The second line: how it connects, its status, which tafs use it | `line`, as sent; for an app an operator sets up first, its `words` |
| "Company" or "Yours" | `whose`, as sent |
| How it connects | `method`, else `how`, through the shared lines `connect.how.*` |
| Which tafs use it | `used_by[].name`, through `connect.apps.used_by`; a user that doesn't read is left out |
| Which list it is in | `state`: `connected` and `needs_reconnect` are **Yours**, the rest **Discover** |
| The app's icon | `logo`, only as tafs cloud's own `/v1/logos/` and 32 lowercase hex digits (`Apps.logoPath`), as the iPad keeps it; any other address is dropped |
| "Not listed? Ask Coach" | `by_key`: `true` only; anything else reads as false |

- A connection to sign in again has its line in amber.
- A row this app can't read is left out. An answer with no list is unreadable, never "No app
  by that name."
- `partial` says tafs cloud's read stopped early: then "No app by that name." is not shown,
  since an app that isn't listed isn't absent.

## The screen (`ConnectAppsView`, `ConnectAppsModel`)

Laid out as the iPad's: the large title with the search box at its top right, then two
panels.

- **Yours** is a table with the iPad's columns (`ConnectColumns`: the app at least 200 wide,
  How 150, Whose 130, Status 230, 12 apart): **App** (the app's 24-point icon when tafs cloud
  sends one and nothing otherwise, its name and what this entry is), **How it connects** ("With a key" when tafs cloud's `method`, or an older
  one's `how`, is `key`; else "Sign in", as the iPad decides it), **Whose** (`whose`, as
  sent), and **Status**: "Connected" in green or "Sign in again" in amber, with **"Used by
  …"** under it, the names in `used_by` as the language lists them.
- **Discover** lists the other apps in the same columns, with the headings over it when
  there is no Yours. An app an operator sets up first is named in the soft colour, with tafs
  cloud's `words` in its Status cell.

- **Each row ends as the iPad's** (`trailing`): a green check for a connected app; nothing
  for one an operator sets up first; else an outlined **Connect**, or **Sign in again**, as
  wide as its words (`OutlineButtonStyle`: 15 medium, at least 48 high, a 14-radius stroke at
  40%). The iPad's chevron on a connected row is left out: a connection has no page of its
  own here yet.
- **"Not listed? Ask Coach"** ends the screen only while tafs cloud says Coach can connect an
  app by key (`by_key`). A new search asks again; the next page of one keeps it.
- Search by name; Return searches. What is typed is escaped and cut at 100 characters.
- **Show more apps** reads the next page of the same search. An app already listed isn't
  listed twice.
- A slower answer to an older search is dropped.

## The receipt (`ConnectReceipt`, `ConnectReceiptSheet`)

Once an app is connected, a receipt confirms it, as the iPad's `ConnectApprovalSheet.receipt`
(kiff/tafs `ios/Tafs/Views/ConnectAppsView.swift:952-981`), with board 5, an app connected
(docs/window.md › Illustrations).

- **When it shows.** On this Mac an app is connected through Coach, and its approval and sign-in
  are made on the phone. The Mac sees the sign-in finish when Coach's chat, read again, marks a
  connection card it showed without its connection made as made: tafs cloud's
  `connection: {done: true}` on an approval or a sign-in card (`Thread.Card.connected`),
  which it sets only once planque shows the connection connected. The receipt is the newest
  such card's (`ConnectReceipt.made`). None on a first read, for a card first seen already
  connected, for a card not made, between two different chats, or in a taf's own chat.
- **Coach is read again while a connection waits** (`CoachModel.watchConnection`): while
  Coach's own chat has a connection card not made yet that waits for the person, or whose run
  is at work (approved on the phone, its sign-in under way), the chat is read every 4 seconds,
  the phones' pace, at most 75 times, and only while Coach is on screen. A message on its way
  or an answer being written has its own reads. Only `GET`. Coming back to Coach reads it too,
  so a sign-in finished meanwhile shows its receipt then.
- **The sheet** is the iPad's receipt, over Coach, 460 wide: board 5 at its own width (280, 123
  high), the heading (a green lock, then tafs cloud's title for the card in 22 bold, else the
  app's name as the card names it), a green check with tafs cloud's line for the connection
  in 16 semibold ("Qonto is connected (read only)"), else the shared "Connected"
  (`connect.status.connected`, the iPad's own fallback), and **Done** (`common.done`, the
  brand's button, Return), which closes it.
- **Where it differs from the iPad's:** no logo or host in the heading, and no last 4
  characters in the line: they are the key sheet's, and Coach's card carries neither; no
  Disconnect, which asks for an approval.

## Setting planque up (`PlanqueEnrolment`, `PlanqueClient.enrol`)

The first part of connecting an app through Coach, ported from the iPad's `enrolPlanque`
(`AppModel.swift:6267-6310`), `PlanqueClient.enrol(deviceKey:connectorKey:)`
(`PlanqueClient.swift:107-111`) and `KIFFClient.mintConnectorKey` (`KIFFClient.swift:1406-1411`).
planque keeps a taf's vendor sign-ins, so they never reach this Mac, tafs cloud, the agent or
KIFF. It gets this device's key, and a KIFF key that connects tools and does nothing else.

- **Asked first with no key.** `POST /v1/accounts/{tenant}/enrolment` with `{device_key}`. An
  answer with `kept: true` is done, and nothing is minted.
- **A key is minted and handed over only on `409 needs_key`.** A 2xx without `kept` mints
  nothing and says connecting apps isn't set up, as Windows and Android: planque answered
  oddly, and a key minted then could be left live in KIFF, where no device can revoke it. The
  mint is `POST /v1/keys` with `{"label": "planque", "roles": ["connector"]}`, a signed setup
  call. Its plaintext goes straight to planque in `{device_key, connector_key}`, and is never
  kept on this Mac. **Once minted, it is handed over even if the session ends then**: dropping
  it would leave it orphaned. The end is checked after.
- **Anything else stops with why and mints nothing:** planque not reached, a 400, a 5xx, a
  replayed signature, a changed enrolment. A second enrolment would likely fail too, and leave a
  key live in KIFF that no device can revoke; the next try asks again.
- **KIFF's 403 on the mint:** only an admin can connect apps (`coach.connect_admin_only`).
- **planque's code-less 409, on either enrolment:** another device connects this account's
  apps (`coach.connect_other_device`). A 409 with a code says why.
- **Anything else:** "Connecting apps isn't set up. {why}" (`coach.connecting_not_set_up`),
  with planque's own words, else the app's plain line for the status; never a code.
- **A session that ends while it runs** does nothing more and says nothing, as the iPad's
  `gen != accountGeneration`: the caller passes the account check (`ended`), read where the
  iPad reads it (`AppModel.swift:6275`, `:6290`, `:6307`) and first in each refusal. A request
  the system cancelled is the same. A sign-out doesn't cancel the task, so a key minted just
  before is still handed over.
- **Keys:** the enrolments are signed by this Mac's device key, which asks no one, as the
  iPad's `signConfirmed`; so is the mint, at `SigningTime.next()` (milliseconds, never the same
  twice, as `KIFFClient.swift:1625`). Neither uses the approval key.
- **Who may run it (the gate)**, as the iPad's `setUpPlanque` and `startSetup`
  (`AppModel.swift:6230-6249`, `:7556-7575`):
  - only after the person confirmed the step, with Touch ID or the Mac's password over
    `tafs.planque.v1|{tenant}`, or inside Start's own Touch ID (`:7567`);
  - never in a view-only session, or one without a device key (`:6231`);
  - the account is checked after the prompt (`:6241`, `:7569`);
  - planque's `signer` is set only after the prompt, and cleared when the step ends (`defer`,
    `:6246-6247`, `:7574-7575`).
  Nothing calls it before that gate: Start brings the first caller (#106).
- **Where this Mac differs from the iPad:**
  - a 2xx without `kept` mints nothing (the iPad's `AppModel.swift:6276-6279` falls through to
    the mint), as its own comment (`:6270-6271`), Windows and Android;
  - a key minted just before the session ended is handed over, then it ends (the iPad returns
    at `:6293` and drops the key, which stays live in KIFF).

## Not yet

Connecting and signing in again from this screen, removing access, and a connection's
detail.
Each of the first three changes what a taf may do, so each comes with its approval.

## Tests

`scripts/test.sh connections`: the catalog as tafs cloud sends it, rows that don't read, the
two lists, a search's escaping and limit, paging without repeats, an unreadable catalog, the
logo paths kept and dropped, each row's end, `by_key`, and **that nothing but `GET` is ever
sent**. It writes `build/screenshots/connect-apps-*.png`. Setting planque up: kept, `needs_key`
then one key minted and handed over, a 2xx without `kept` minting nothing, a key handed over
when the session ends right after its mint, every stop that mints nothing, the code-less 409,
KIFF's 403, no device or signer, a session that ends during the first enrolment (no mint), the
system's cancellation of the hand-over (ended, never "not set up"), each stop's words, and (on a
Mac) the three signatures checked as planque and KIFF check them, at three different times.

The receipt (`ConnectReceiptTests`, and on a Mac `ConnectReceiptScreenTests`): when it shows
(an approval or a sign-in made between two reads, in tafs cloud's words or the shared
"Connected"), when it doesn't (a first read, a card first seen made, one not made, a card that
isn't a connection, another chat, a taf's chat), the newest of two, board 5, its words in the 8
languages, when Coach is read again and that it stops (made, at its limit, cancelled, only
`GET`), Done, and the sheet on the theme's ground in light and dark. It writes
`build/screenshots/connect-receipt-*.png`, and board 5's `board-5-connect-receipt-*.png`.
