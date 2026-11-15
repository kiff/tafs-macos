# Connect apps

The account's own connections, then the catalog of apps a taf can use. **This screen lists.**
An app is connected through Coach, where its Card is approved with it, so the row's Connect
and Sign in again, and "Not listed? Ask Coach", open Coach. This screen sends nothing but
`GET`.

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
  `accountGeneration`.
- **Keys:** both the enrolment and the mint are signed by this Mac's device key, which asks no
  one, as the iPad's `signConfirmed`. Neither uses the approval key. Who may set planque up, and
  behind what confirmation (the iPad's `setUpPlanque`, a Face ID over
  `tafs.planque.v1|{tenant}`), comes with Start in the next part, with the calls that run it.

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
when the task ends right after its mint, every stop that mints nothing, the
code-less 409, KIFF's 403, no device or signer, a session that ends, each stop's words, and (on a
Mac) both signatures checked as planque and KIFF check them.
