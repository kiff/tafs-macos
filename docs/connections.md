# Connect apps

The account's own connections, then the catalog of apps a taf can use. **This screen lists.**
An app is connected through Coach, where its Card is approved with it, so the row's Connect,
Ask Coach and Sign in again, and "Not listed? Ask Coach", open Coach. This screen sends nothing
but `GET`. A connected app's chevron opens "Your {app} connections", which only reads. Once the app is connected, its receipt shows over Coach (below, "The receipt").

## What is read (`Apps`, `CloudClient.apps(_:cursor:)`)

`GET /v1/connect/apps?q=&cursor=` on tafs cloud, with this Mac's signed read of its connections
(`Planque-Device-Signature`), as the iPad's `loadConnectApps` sends it (`AppModel.swift:2756-2761`),
so tafs cloud names the removed tafs' connections. A fresh one each read: planque takes each once.

| Drawn | From |
|---|---|
| The row's name | `name` (an older tafs cloud's `title`). Never `vendor`, which is a key. |
| What this entry of the app is | `subtitle` |
| The second line: how it connects, its status, which tafs use it | `line`, as sent; for an app an operator sets up first, its `words` |
| "Company" or "Yours" | `whose`, as sent |
| How it connects | `method`, else `how`, through the shared lines `connect.how.*` |
| Which tafs use it | `used_by[].name`, through `connect.apps.used_by`; a user that doesn't read is left out |
| Which list it is in | `state`: `connected` and `needs_reconnect` are **Yours**, the rest **Discover** |
| The app's icon | `logo`, only as tafs cloud's own `/v1/logos/` and 32 lowercase hex digits (`Apps.logoPath`), as the iPad keeps it; any other address is dropped. Read through `AppLogos` (below, "Logos") |
| Which tafs need it | `needed_by[]` (`taf`, `name`), for the button's words; a list that doesn't read is none sent |
| Its connection, and those made for a taf that doesn't use it | `grant`, `misplaced[]`, for its page |
| The tafs removed since | `removed_tafs[]` (`agent`, `grants[].used_by`), for its page |
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
  for one an operator sets up first; else an outlined button as wide as its words
  (`OutlineButtonStyle`: 15 medium, at least 48 high, a 14-radius stroke at 40%), in the iPad's
  words (`connectFor`, `ConnectAppsView.swift:195-220`, `:345-367`; `Apps.buttonKey`): **Ask
  Coach** where tafs cloud says which tafs need the app (`needed_by`) and none of them is a taf
  this person manages on tafs cloud; else **Sign in again**, or **Connect**. Each opens Coach,
  where an app is connected on this Mac. Where no taf can have the app (no `needed_by`, and
  no taf this person manages on tafs cloud), Connect is off, as the iPad's (`route == .noTaf`,
  `Apps.route`), and Discover's panel opens with "Apps connect for a taf. Make one first, then
  connect its apps here." (`connect.apps_connect_taf_make_one`, `Apps.saysMakeATaf`, the iPad's
  `ConnectRow.saysMakeATaf`, `ConnectAppsView.swift:410-412`). Never over Yours.
- **The chevron** past Status, on a row whose connections open (`AppConnections.opens`, the
  iPad's `opensConnections`: connected, or holding a connection on this account), opens "Your
  {app} connections" in the screen's place; so does a click anywhere on a connected row.
- **"Not listed? Ask Coach"** ends the screen only while tafs cloud says Coach can connect an
  app by key (`by_key`). A new search asks again; the next page of one keeps it.
- Search by name; Return searches. What is typed is escaped and cut at 100 characters.
- **Show more apps** reads the next page of the same search. An app already listed isn't
  listed twice.
- A slower answer to an older search is dropped.

## Logos (`AppLogos`, `AppLogoImages`, `AppLogo`)

Each app's logo, beside its name in Connect apps (24 points) and in the jobs' apps (`AppMark`, 18
points, docs/overview.md).

- **Why they were empty on macOS 12.** The rows asked for `logoURL` with SwiftUI's `AsyncImage`,
  as the iPad does. Neither suspect is the cause: tafs cloud's route takes no session
  (`runtime/src/cloud/handler.ts:653-654`, "no session, as image loaders send none"; asked
  without one, it answers 404 for a key it doesn't keep, never 401), and it answers `image/png`,
  a PNG tafs cloud drew itself, from an SVG source too (`handler.ts:10443-10456`,
  `logos.ts:149-165`). What differs from every read that works on that Mac is `AsyncImage`
  itself: it reads outside the app's own transport, through `URLSession.shared`, and a load that
  fails or is ended early stays in its failure phase, never asked again, which the row draws as
  nothing. That wasn't seen on a Mac on macOS 12 here; the logos no longer depend on it.
- **Read through the app's own transport** (`AppLogos`), to tafs cloud's address only
  (`NetworkTransport` refuses any other host): `GET /v1/logos/<key>` with
  `Accept: image/png, image/jpeg`, and **no session**, as the route asks and the iPad sends.
- **Only `/v1/logos/` and 32 lowercase hex** (`Apps.logoPath`); any other address is dropped,
  and nothing is asked for it.
- **Kept in memory per path** for the session; one being read isn't asked again meanwhile. A
  PNG or a JPEG (by its first bytes, at most 512 KB) is decoded once into an `NSImage`
  (`AppLogoImages`), and drawn in the first frame after.
- **A refusal (tafs cloud's 404), bytes that aren't a PNG or a JPEG, or an image that doesn't
  decode keep nothing:** the square stays empty in Connect apps, and a job's app is its name
  alone. It is asked again the next time it shows.

## Your {app} connections (`AppConnections`, `ConnectionsSource`, `AppConnectionsView`)

A connected app's connections, as the iPad's `AppConnectionsView` (`ConnectAppsView.swift:488-722`)
and its model (`AppModel.swift:7025-7083`). It only reads.

- **Read** from planque, as the iPad's `PlanqueClient.grants(signedBy:)`:
  `GET /v1/accounts/{tenant}/grants` on planque, the tenant escaped (`CloudClient.escaped`),
  with this Mac's signed read (`Planque-Device-Signature`, `PlanqueClient.grantsReadProof`,
  signed by the device key with this device's id, asking no one, as Coach's read of the same
  proof is). Read with Connect apps' first page, as the iPad's `loadConnectApps` does. A grant
  that doesn't read is left out. An answer with no list, a refusal, or a session with no device
  key reads none, and the page says "Start from Connected apps on this Mac first."
  (`connect.start_connected_tools_first`), never an empty list.
- **An app's connections** are those with its entry, or the grant tafs cloud named for it,
  never a disconnected or failed one.
- **Grouped** by the taf each was made for (a listed taf, by its KIFF agent): one needing
  attention (waiting on its sign-in, or signed out) first, then by name; then **From removed
  tafs**, only for agents tafs cloud names as removed; then **Other connections**, whose taf
  this Mac can't name.
- **A connection's row**: planque's own row when it sends one (its name, "Used by …", its
  health in its words, amber when it isn't ok); else its name (planque's `title`, else the
  account it names, else the app's), planque's words for its status or "Waiting for the sign-in
  at …", and "Made for {taf}, which doesn't use {app}." for one tafs cloud names `misplaced`.
  planque's own row (its health and its `actions`) opens **the connection's page**, below.
- **What would change a connection** is drawn as on the iPad, for whoever manages the Cards:
  **Sign in again** or **Replace the key** (a provider's connection says to remove it and connect
  it again), **Remove access**, **Cancel the request** or **Cancel**, and **Clear these
  connections** under the removed tafs' (only when tafs cloud lists one with no live taf's Card
  using it; a kept one says whose Card uses it). **The iPad's question comes first** where the
  iPad asks one (`GateQuestion`): Remove access asks "Remove access to {vendor} for {taf}?" with
  what stops (the iPad's `DisconnectWords`: `AppConnections.disconnectTitle`, `disconnectMessage`,
  the key's own line for a key); Cancel asks "Cancel the request for …?" or "Cancel the sign-in to
  …?" with Keep waiting (`ConnectionFixWords`: `cancelTitle`, `cancelWordKey`); Clear asks "Clear
  {count} connections from removed tafs?" with its body. This Mac can't sign them: on its yes (or
  the click, for Sign in again and Replace the key, which the iPad doesn't ask) it shows "This
  device can't approve. Approve on another device signed in to your account."
  (`approval.device_can_not_approve_approve`) under it, and sends nothing. The questions name no
  other taf whose Card also stops: this Mac doesn't read which Cards use a connection's tools.
- The footer, "Removing access takes its tools from that taf only, …", shows for whoever
  manages Cards when a connection here is a taf's.
- **Back** ("Connect apps") returns to the list.
- **The connection's page** (`ConnectionDetailView`, the iPad's `ConnectAppsView.swift:1181-1262`),
  in the page's place, with Back to "Your {app} connections": its name (else the app's), its
  health in planque's words (ink when ok, else amber), "Used by …", and, for whoever manages the
  Cards, the actions planque says work for it now (`actions`, read as the iPad's `Grant.Action`:
  only a known one with its words, `Action.known`: Sign in again by `approve` or `key`, Remove by
  `delete`), in planque's words and order, Remove's in red. Remove asks first in planque's words,
  with what stops (`stops`); then each says to approve on another device and sends nothing.
- **Left out:** a connection's last failed call (KIFF's calls by tool aren't read here), and
  "Also on …'s Card" (the Cards' actions by tool aren't read here), as on Linux.

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
  high); the heading, a green lock and then, on the same line in 22 bold, tafs cloud's title for
  the card, else the app's name as the card names it (a sign-in's `service`), else the card's
  own words; a green check with tafs cloud's line for the connection in 16 semibold ("Qonto is
  connected (read only)"), else the shared "Connected" (`connect.status.connected`, the iPad's
  own fallback); **Done** (`common.done`, the brand's button, Return), which closes it; and
  **Disconnect**.
- **The heading is never empty** (`ConnectReceipt.title`). A card that names nothing heads with
  tafs cloud's line, else "Connected", and the check's line under it is then left out, so
  nothing is said twice.
- **Disconnect** is the iPad's (`:965-978`), drawn in the shared "Remove access"
  (`connect.disconnect_button`) for whoever manages the account's Cards (KIFF's `cards.manage`),
  as the iPad's `canManageCards`. This Mac can't sign the disconnection, so a tap asks nothing
  and sends nothing: it shows "This device can't approve. Approve on another device signed in
  to your account." (`approval.device_can_not_approve_approve`), as every approval this Mac
  can't make shows in place of the iPad's `ApprovalGate` (docs/approvals.md).
- **Where it differs from the iPad's:**
  - No logo or host in the heading: they're the iPad's key sheet's, and Coach's card doesn't
    carry them yet. They'll be drawn once tafs cloud adds them to the card.
  - No last 4 characters in the line: this Mac never holds the key.
  - The iPad's Disconnect words are tafs cloud's, from the key sheet; here they're the shared
    ones.

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

## Not on this Mac

Connecting and signing in again from this screen, giving or replacing a key, removing access, and
clearing the removed tafs' connections. Each is approved at planque, signed by a device key that
grants (the iPad's Face ID key, Windows' TPM key behind Windows Hello); this Mac's device key
grants nothing, and planque takes no security key, so "Nothing is approved at planque from this
Mac" (docs/approvals.md). Each is drawn up to its approval, which is made on the phone. So are
the approval sheet's own parts (the approval, the key's sheet, the receipt's logo, host and last
4 characters): the receipt over Coach has no grant to read them from, and this Mac never holds a
key.

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
`GET`), Done, the heading never empty, Disconnect only for whoever manages the Cards and its tap
saying to approve on another device, and the sheet on the theme's ground in light and dark. It writes
`build/screenshots/connect-receipt-*.png` (with `connect-receipt-disconnect-*`), and board 5's `board-5-connect-receipt-*.png`.

Logos and a connected app's page (`AppLogosTests`, `AppConnectionsTests`, and on a Mac
`AppConnectionsScreenTests`): a logo read from tafs cloud's own path with what asks for an image
and no session; any other address dropped, with nothing sent; a logo kept per path and read
once, at the same time too; a refusal, an SVG, JSON, nothing, too much or a failed read keeping
nothing, and asked again; a PNG that doesn't decode keeping nothing; the logo drawn in its square
while a refused one leaves it empty. The connections read from planque with this Mac's signed
read (the tenant escaped, no session, no read without a proof, a refusal and an answer with no
list never "no connections"), signed over planque's message with the device id; an app's
connections; the groups in the iPad's order; the removed tafs' and Clear; each connection's end;
the catalog read with the proof, `needed_by` and `misplaced`; planque's actions read as the
iPad's (only a known one with its words, Remove the one that ends it, `stops` trimmed, a list that
doesn't read is none); the questions before Remove access and Cancel, in the iPad's words; "Make
one first" and Connect off for no taf; and the page's words in every shipped language. It writes `connect-apps-logos-en.png` and `connect-app-connections-en.png` (each with
its `-dark` twin), `connect-app-connections-gated-en.png` (Remove access clicked) and
`connect-app-connections-opened-en.png`, `connect-connection-page-en.png` (with its `-dark` twin and `-gated`) and `connect-apps-make-one-first-en.png`.
