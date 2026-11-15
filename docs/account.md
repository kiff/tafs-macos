# The signed-in Mac

What a Mac does once it has a session: how its requests go to KIFF, and the devices of the
account. Getting the session is in [pairing.md](pairing.md); the keys are in
[signing.md](signing.md).

## The session

- `SessionStore` keeps the session in the Keychain between launches, and nowhere else.
- `forget()` removes it at sign-out, and when KIFF answers that it no longer knows the
  session (`KIFFError.endsSession`, a 401): the app then shows sign-in again.

## Requests (`AccountClient`)

Every request carries:

- the session (`Authorization`);
- the language the app shows (`Accept-Language`), so KIFF's own lines come in it;
- for a route KIFF wants signed (`signed: true`), the device key's signature over the exact
  bytes sent. A signed request is never sent without a key.

A refusal throws KIFF's own code. An answer that isn't the contract's shape is unreadable:
it is never shown as an empty list.

## Devices

| Call | Route | What |
|---|---|---|
| `devices()` | `GET /v1/me/devices` | Each device: KIFF's name for it, its platform, when it was last used, and which one is this Mac. Its key's fingerprint isn't read: no screen shows it. |
| `removeDevice(_:)` | `DELETE /v1/me/devices/{id}` | Signs that device out. Its session and any approval window it opened end at once. |
| `signOut()` | `POST /v1/auth/device/logout` | Ends this Mac's session. |

The Devices screen (Account) draws this list in its own pull request.

## Tests

`scripts/test.sh account`: the headers of each request, the devices list as KIFF sends it
(with and without each optional field), an unreadable answer, a removed device's path, a
session that ended, and a signed request checked with the device key. No test reaches the
network.

## The Devices screen

`DevicesView`, driven by `DevicesModel`, lists every device of the account (Account → Devices):

- as the iPad's row: KIFF's name for it (15 semibold) and when it was last used (13 dim).
  No key fingerprint, as on the iPad: keys are compared at pairing, through the 6-character
  check code both screens show ([pairing.md](pairing.md));
- "This device" on this Mac's own row.
- **Every row opens its device**, in a sheet with its name and when it was last used, so a
  click is never a dead end.

**Signing another device out is an approval**, since it can take away the account's power
to approve. So:

- **On a Mac that can't sign an approval** (every Mac today, approving on the phone or with a
  passkey), another device's sheet has no Sign out. It says the shared line "To sign another
  device out, use a device that can approve." (`settings.devices.signout_needs_approver`),
  and the model sends no removal even if asked. KIFF refuses it with `view_only` anyway.
- **Before any Mac may sign another device out,** that removal becomes the iPad's signed
  approval (`prepareRemoveDevice`, then `signApproval`), not a bare `DELETE`. Until then
  `canRemoveOthers` stays off on every Mac, and the `DELETE` is never reached.
- **Where this Mac may**, the sheet has Sign out, which asks first, naming the device (the
  iPad's `confirmationDialog`). After a removal the list is read again from KIFF. KIFF's
  refusal for want of an approval shows "This device can't approve…"; any other refusal says
  why and leaves the list as it was.

**This Mac's own sheet has Sign out**, as Account's: it asks first ("Sign out of KIFF?"),
then KIFF ends the session and the Mac forgets it. A view-only device can always leave.

`scripts/test.sh account` writes `build/screenshots/devices-*.png`.
The screen's own reads (its `.task`, run as often as macOS draws it) are never counted: a
test that draws the screen draws it from a model of its own, and the model under test sees
only the calls it makes.

## The Account page (`AccountView`, `AccountModel`)

To the iPad's layout: a large title and grouped panels of rows. Rows are 17, the list's body
size on the iPad; each group's heading is 17 semibold in the soft colour.

| Group | Rows |
|---|---|
| Your account | Mode ("Signed in with KIFF"); **KIFF account**, the account's name (else its slug); and **Signed in as**, the email, left out when it is the account's own name. From `GET /v1/me`. |
| View only | **Only when KIFF says this session is `view`** (`approval_mode`): what a view-only Mac does, and **Add this Mac**. A KIFF that doesn't say, and a session it calls `passkey` or `key`, show no such group. |
| People & apps | Devices (opens the list), Connect apps. |
| Plan | Always there. tafs cloud's `plan_line` at 16 semibold in `plan_tone`'s colour (red waiting, amber warning), then "Plan & usage"; just "Plan & usage" when the balance can't be read. It opens Plan & usage. |
| Theme | Light, Dark, or System. Kept for the next launch and applied to the whole app. |
| Language | **Language**, the app's language by its own name ("Français"), then **Change language** in amber, which opens macOS's Language & Region, where a language is chosen for one app. The app declares every shipped language (`CFBundleLocalizations`) so macOS lists it there; a test keeps that list the shipped one. |
| How it works | The shared line. |
| Legal | Terms and Privacy policy, on kiff.dev. Only those two pages are ever opened from here. In any language but English each says "(in English)", as on the iPad. |
| About | **Version**, the version and its build ("0.1 (1)"), then the tagline in dim. |
| Account actions | Sign out, **confirmed first** with the iPad's words ("Sign out of KIFF?", a destructive Sign out, and Cancel), so a stray click never ends the session. |

- **Where View only comes from.** The Mac reads KIFF's contract field: `GET /v1/me` gives the
  calling session's `approval_mode`. (The phones learn it from a `403 view_only`.) When
  `/v1/me` can't be read, or a session from before approval modes doesn't say, the page shows
  no View only group and so claims nothing: KIFF refuses a view-only session's approvals
  anyway.
- **`/v1/me` is read once** by the window; the page reads it again only if that read failed.

Each line is read on its own: one that can't be read is left out, never the page.

The sidebar's Account button shows the same `GET /v1/me` under it: the email, else the
account's name. With neither, it shows nothing under Account.

## People & groups (`People`, `PeopleModel`, `PeopleView`)

Ported from the iPad's `PeopleViews.swift` (`PeopleGroupsView`) and `KIFFClient`'s `Group`,
`GroupMember` and `Person`. The first row of People & apps opens it.

| Read | From | Drawn |
|---|---|---|
| The groups | KIFF's `GET /v1/groups`: `id`, `name`, `everyone`, `members` (`subject`, `role`), `agents` | Each group's name, KIFF's default one ("Everyone") in the app's language; "Uses {tafs}", the tafs by name from the agents it is shared, or that it uses none; then its people, managers first, then by label. |
| The people | KIFF's `GET /v1/tenant/members`: `subject`, `role`, `status`, `email`, `you` | A person as their email, else KIFF's id for them, with their initial on a raised circle, and "Manager" (amber) or "Member". |

- **Who and in what order,** as the iPad's `refreshPeople`: only the people on the account now
  (`status` active), by label; the default group first, then the others by name, case aside.
- The line over the groups is the account's name and how many people, or the count alone
  for an account named after its owner's email, as the iPad's `AccountLines.people`. The Mac
  also gives the count alone when KIFF names no account, which the iPad's account always has.
- Read when it opens and every 20 seconds while open (the two lists one after the other, where
  the iPad reads them together). A read that fails after one that worked keeps what is shown,
  with "People and groups couldn't be read" over it until a read works; a first one says why.
- "No groups" shows only for lists that read with none and no read failed since, as the
  iPad's `loaded && groups.isEmpty && peopleError == nil` (`PeopleViews.swift:42`).
- Decoded as the iPad's: a group's members and agents, and a person's role and status, must
  be there; one that doesn't read fails the read, which says why.
- **It only reads.** Making, renaming or deleting a group and changing its people are each
  the person's act behind their device's key on the iPad, so on the Mac they come with
  approvals (#16).

## Alerts (`AlertPrefs`, `AlertsView`)

Ported from the iPad's `NotificationSettingsView`: Account › Alerts, a row on its own.

- What an alert looks like: a loud one and a silent one, in the shared words, with the
  app's mark (the iPad's `LockScreenAlert`).
- **Alerts on this Mac** is on only once the person turned it on **and** macOS allows tafs to
  alert, as the iPad's (`AppModel.swift:1639-1651`). Turning it on asks macOS first; refused,
  it says `alert.allow_notifications` and stays off. It's read again from macOS each time the
  screen opens, so turning notifications off in System Preferences shows it off.
- **The choice is kept per account** (`tafs.alerts.on|{tenant}`), as the iPad keys it by tenant
  (`alerts.enabled|{tenant}`, `AppModel.swift:89`): an account that signs in on this Mac never
  inherits another's. **Sound** ("For a hold or a halt only") is the Mac's, on until turned
  off, as the iPad's `alertSound`; it's off and greyed while alerts are off, its choice kept.
- **`Notifier`** announces a call only once alerts are on for the signed-in account. With
  Sound off an alert still arrives, quietly: no sound and no banner, only Notification Center
  (`interruptionLevel` `.passive`, and `[.list]` with the window in front), as tafs cloud
  sends the iPad's (`interruption-level: passive`).
- Needs you's "Know the moment a taf needs you" card isn't drawn: its line promises alerts
  "even with tafs closed", which a Mac without a signed build can't keep.
- On the Mac an alert comes while tafs is open: a push with the app closed needs a signed
  build, so this screen never says alerts come with tafs closed. What alerts the account's
  phones is kept per phone by tafs cloud (`GET /v1/push`, by the phone's token), so it isn't
  listed here. Haptics are the phone's.

Not on the Mac yet: Coach's suggestions, AI use, Time zone, and Export my chats.
Their rows come with their screens: a row that opens nothing isn't drawn.

## Export my chats

As the iPad's `ExportChatsSection`, `exportChats` and `splitExport` (`ExportChatsView.swift:7-63`,
`AppModel.swift:4662-4674, 5594-5618`, `TafsCloud.swift:1517-1530`): the person's own chats,
trials and notes, for their rights of access and portability.

- **Export my chats** (Try again after a failure) reads `GET /v1/me/chats/export` and writes
  two files: `tafs-chats.json` (tafs cloud's export, its `readable` text taken out, pretty and
  sorted) and `tafs-chats.txt` (that text).
- They're offered at once in macOS's share menu, the Mac's share and save sheet. The row then
  names them, to share them again.
- A read that fails says to check the connection; files that couldn't be written say so.
- The files are written to a temporary folder, replaced at each export, and removed at every
  session change: a sign-out, a sign-in, and a pairing that replaces this Mac's session
  (`SignInModel`), as the iPad's `removeOpenedFiles` in `useSession` and `forgetSession`
  (`AppModel.swift:879`, `:1334`). So a person's chats never stay on the Mac after them.

