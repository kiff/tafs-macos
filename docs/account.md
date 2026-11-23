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

| `passkeys()` | `GET /v1/me/passkeys` | The account's passkeys, read unsigned as the devices are, as the iPad's `passkeys()`: a person's own (its `id`), or a computer's own (`device_id`, no id), which goes with its computer. |
| `setTimeZone(_:)` | `PUT /v1/me/time-zone`, signed | Sets the account's time zone (`{"time_zone"}`), signed by the device key, as the iPad's signed setup call. KIFF answers the zone it keeps. |

tafs cloud's side of Account (`CloudClient`, `Core/account/AccountControls.swift`):

| Call | Route | What |
|---|---|---|
| `suggestions()`, `setSuggestions(_:)` | `GET`, `PUT /v1/me/suggestions` | Coach's "Show suggestions": `show` and tafs cloud's `words` for it. |
| `aiConsent()`, `giveAIConsent(version:)`, `withdrawAI()` | `GET`, `POST`, `DELETE /v1/me/ai-consent` | The AI-data consent, read, given for the version of the words read, and withdrawn. A yes to older words is refused (409) with the newer ones. |
| `timeZones(_:)` | `GET /v1/time-zones?q=` | The picker's zones for a search: each `id` and `title`. |
| `syncTimeZone()` | `POST /v1/account/time-zone` | tafs cloud takes the account's zone from KIFF again, for the tafs' schedules. |

## Tests

`scripts/test.sh account`: the headers of each request, the devices list as KIFF sends it
(with and without each optional field), an unreadable answer, a removed device's path, a
session that ended, and a signed request checked with the device key; the time zone saved
(confirmed, signed, read again, tafs cloud told), not confirmed, without a key, refused and
half done; the zones' search; the passkeys as KIFF lists them; the AI-data consent read, given
and withdrawn, from tafs cloud's own contract, and a yes to older words; Show suggestions; the
KIFF account page's id and Delete account. No test reaches the network.

## The Devices screen

`DevicesView`, driven by `DevicesModel`, lists every device of the account (Account → Devices):

- as the iPad's row: KIFF's name for it (15 semibold) and when it was last used (13 dim).
  No key fingerprint, as on the iPad: keys are compared at pairing, through the 6-character
  check code both screens show ([pairing.md](pairing.md));
- "This device" on this Mac's own row.
- **Every other device has the iPad's red Sign out at its row's end** (`DevicesView.swift:16-40`).
- **Every row opens its device**, in a sheet with its name and when it was last used, so a
  click is never a dead end.
- Under the list, the iPad's footer (`settings.devices.note_device`).
- **Add this Mac**, with the computer mark, while this Mac is view-only with a Secure
  Enclave key: the Mac's own pairing, in the place of the iPad's **Add a device**, which
  pairs another computer from the phone (`PairComputerView`, not for macOS 12).
- **Passkeys** (`DevicesPasskeys`, the iPad's `passkeys` section, `DevicesView.swift:86-128`),
  read-only: each passkey by its name ("Unnamed" without one), and a computer's own security
  key saying it goes with its computer (`settings.devices.passkey_with_computer`). Read with
  the list when Devices opens; a read that fails says why (`settings.devices.passkeys_not_loaded`)
  and keeps what was read. Drawn only with something in it. Remove and Add are the iPad's, for
  a session that approves: no Mac does yet.

**Signing another device out is an approval**, since it can take away the account's power
to approve. So:

- **On a Mac that can't sign an approval** (every Mac today, approving on the phone or with a
  passkey), the row's red Sign out is drawn, as on the iPad, and **its click sends nothing**: it
  says "This device can't approve. Approve on another device signed in to your account."
  (`approval.device_can_not_approve_approve`) under the list (`signOutClicked`). Another
  device's sheet has no Sign out: it says "To sign another device out, use a device that can
  approve." (`settings.devices.signout_needs_approver`), and the model sends no removal even
  if asked. KIFF refuses it with `view_only` anyway.
- **Before any Mac may sign another device out,** that removal becomes the iPad's signed
  approval (`prepareRemoveDevice`, then `signApproval`), not a bare `DELETE`. Until then
  `canRemoveOthers` stays off on every Mac, and the `DELETE` is never reached.
- **Where this Mac may**, the sheet has Sign out, which asks first, naming the device (the
  iPad's `confirmationDialog`). After a removal the list is read again from KIFF. KIFF's
  refusal for want of an approval shows "This device can't approve…"; any other refusal says
  why and leaves the list as it was.

**This Mac's own sheet has Sign out**, as Account's: it asks first ("Sign out of KIFF?"),
then KIFF ends the session and the Mac forgets it. A view-only device can always leave.

`scripts/test.sh account` writes `build/screenshots/devices-*.png`, and Devices with each Sign
out clicked and the passkeys as `devices-passkeys-light.png` and `devices-passkeys-dark.png`.
The screen's own reads (its `.task`, run as often as macOS draws it) are never counted: a
test that draws the screen draws it from a model of its own, and the model under test sees
only the calls it makes.

## The Account page (`AccountView`, `AccountModel`)

To the iPad's layout: a large title and grouped panels of rows. Rows are 17, the list's body
size on the iPad; each group's heading is 17 semibold in the soft colour.

| Group | Rows |
|---|---|
| Your account | Mode ("Signed in with KIFF"); **KIFF account**, the account's name (else its slug), which opens the KIFF account page (below); and **Signed in as**, the email, left out when it is the account's own name. From `GET /v1/me`. |
| View only | **Only when KIFF says this session is `view`** (`approval_mode`). On a Mac with a Secure Enclave: what a view-only Mac does, and **Add this Mac**. On a Mac whose device key is a software key, adding it with the phone still leaves it view-only, so there's no Add: the shared line for such a computer, "This computer approves only through your phone or a passkey." (`settings.devices.pair_software_key`). A KIFF that doesn't say, and a session it calls `passkey` or `key`, show no such group. |
| People & apps | Devices (opens the list), Connect apps. |
| Plan | Always there. tafs cloud's `plan_line` at 16 semibold in `plan_tone`'s colour (red waiting, amber warning), then "Plan & usage"; just "Plan & usage" when the balance can't be read. It opens Plan & usage. |
| Coach | **Show suggestions**, its switch at the row's end, with tafs cloud's words under it for what it does now, where the iPad keeps it (`SignInView.swift:330-344`). Only for someone who may use Coach (`mayUseCoach`), once `GET /v1/me/suggestions` has read; enabled for the people who manage the account's Cards (`cards.manage`). A change refused says so (`settings.suggestions_not_changed`) and keeps the switch as it was. |
| Alerts | A row on its own, which opens Alerts. |
| Theme | Light, Dark, or System. Kept for the next launch and applied to the whole app. |
| Language | **Language**, the app's language by its own name ("Français"), then **Change language**, which opens the app's own list (`LanguagePickerView`): This Mac's language first (`settings.language_device`, offered once that shared line is at the pin), then every shipped language by its own name ("Deutsch", "Polski"), the current one marked. Choosing one keeps it for this Mac (`LanguageChoice`, its own key; none kept follows the Mac's preferred languages) and applies it at once, with no relaunch (`AppLanguage`): the words are read again, and the signed-in window is made again on Account, so every request's `Accept-Language` follows and dates follow the new language with this Mac's region. A kept language that is no longer shipped counts as none. macOS's Language & Region is no longer opened from here. The app still declares every shipped language (`CFBundleLocalizations`); a test keeps that list the shipped one. |
| AI use | The AI-data consent, as the iPad's `AIConsentRow`, every word tafs cloud's: given, its `given` line ("AI use: allowed") and **Withdraw** in red (`DELETE /v1/me/ai-consent`); not given, its title in amber, which opens its screen (`AIConsentSheet`, the iPad's `AIConsentView`: the title, the lines, Not now and Allow). Allow sends the version of the words read; words changed meanwhile come back to be read again. Left out until the consent reads, and when it can't be drawn (`drawable`). |
| Time zone | **Time zone**, the account's zone (UTC when KIFF hasn't said), which opens the picker (below). |
| Export my chats | Below. |
| How it works | The shared line. |
| Legal | Terms and Privacy policy, on kiff.dev, in the app's language where kiff.dev has them: `kiff.dev/<lang>/tafs/terms` and `/privacy` for German, Spanish, French, Italian, Dutch, Polish and Portuguese, else the English pages (`LegalPages`). The English pages govern. Only those two pages are ever opened from here. In any other language each says "(in English)". |
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

Each switch is at its row's end, as the iPad's list toggles (`NotificationSettingsView.swift:12-31`):
macOS draws a switch's own label beside it, so the row draws the label, room, then the switch
(`EndSwitch`), which keeps its label for VoiceOver. Greyed while it can't change.

`scripts/test.sh account` writes `alerts-switches-light.png` and `alerts-switches-dark.png`.

## The KIFF account page (`KiffAccountPage`)

As the iPad's `AccountView` (`SignInView.swift:404-450`), from Account's KIFF account row:

- **KIFF account**, the name; **Account id**, the slug, only when the name isn't it
  (`Me.accountID`); **Signed in as**.
- **Time zone**, which opens the picker, and **Use this Mac's: {zone}** when the Mac's zone isn't
  the account's (`AccountZone.offersDevice`); under them, the shared footer
  (`settings.time_zone.uses_this`).
- **Export my chats**, as on Account.
- **Delete account…**, in red, apart, with what it deletes under it
  (`sign_in.deletes_every_taf_runs_chats`), only for someone KIFF lets delete it
  (`account.delete`). On the iPad deleting is signed by the device key behind Face ID, then
  erases tafs cloud's, planque's and KIFF's sides (`deleteAccount`). **Not on macOS 12:** KIFF
  takes a deletion only when its intent (`tafs.delete-account.v2`) is signed by the session's
  phone approval key (`acceptDeletion` answers `approval_key_required` otherwise), and this Mac
  holds none; there's no security-key or passkey path for it. So the row is drawn, and **its click
  sends nothing**: it says "This device can't approve. Approve on another device signed in to
  your account." (`approval.device_can_not_approve_approve`). There's no Delete account sheet on
  the Mac, and no source names a deletion route (a test pins it).

## The time zone (`TimeZonePicker`, `AccountZone`)

As the iPad's `TimeZonePicker` (`AccountPreferencesView.swift:52-75`): **Use this Mac's:
{zone}**, then tafs cloud's zones for the search (`GET /v1/time-zones?q=`), the account's
ticked. The search is a plain field ("Find a time zone"), read again once typing pauses
(250 ms, as the iPad's `.task(id:)`); only the newest search's answer is kept.

A zone chosen is saved as the iPad's `setAccountTimeZone` (AppModel.swift:356-388):

1. The owner confirms: Touch ID or the Mac's password, saying "Set your account's time zone
   to {zone}" (`settings.time_zone.prompt`). Closed, it says "Cancelled. Nothing changed.";
   failed, "Not sent: it wasn't confirmed." Nothing is sent before.
2. `PUT /v1/me/time-zone`, signed by the device key over the exact bytes sent. A session
   without a device key sends nothing and says to sign in again. Refused, it says
   `settings.time_zone.not_changed` with KIFF's plain why, and nothing else is sent.
3. `GET /v1/me` again, so every time shown is in the new zone.
4. `POST /v1/account/time-zone`: tafs cloud takes it for the tafs' schedules. When it can't,
   KIFF has the zone and the page says `settings.account_zone_changed_schedules_could`.

`scripts/test.sh account` writes the page as `account-settings-light.png` and
`account-settings-dark.png`, the KIFF account page as `account-kiff-light.png` and
`account-kiff-dark.png`, and the picker as `account-zone-light.png` and `account-zone-dark.png`.

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


## Account › Chrome (`ChromesModel`, `ChromesView`, `PlanqueClient.Safe`)

Ported from the iPad's `ChromeViews.swift` (`ChromesView`) to tafs `docs/chrome.md` ("Your Chrome"), as Linux's
tafs-linux#89.
- **Its row**, after Devices, shows only once planque lists Chromes for this person: none while planque doesn't offer
  them (404) or for someone who may only view (403), as the iPad's while `chromes` is nil. Read once with the window.
- **The page:** each Chrome by the name it was paired with, and "{browser} on {system}" when planque knows both;
  "No Chrome is paired." with none; the footer, then **Pair a Chrome**, and the profile note.
- **Unpair**, behind "Unpair {name}": planque ends that Chrome's connections on the same call (planque#364, "Your
  Chrome" 3), so nothing is left pointing at a Chrome that's gone. The list is read again either way. A failure says
  "Unpair {name} didn't go through." with why.
- **Pair a Chrome stays the phone's:** pairing binds the phone's approval key, which the extension then trusts. A
  click says to approve on another device, and nothing is sent.
- **What this Mac signs at planque** widens from its enrolment alone (and the grants read's proof) to planque's safe
  routes, as Linux's `planque::Safe`: `GET …/chromes` and `DELETE …/chromes/{id}`. Each is an empty-bodied request,
  signed by the device key for that one request (`planque.request.v1`), with no session token, on planque's own host.
  None goes through the enrolment's armed signer, which stays armed only around the enrolment. Nothing approves,
  confirms or pairs. planque's safe routes take a software device key.
  `PlanqueRoutesTests` pins both lists.
- **Not here yet:** each Chrome's own connections, and naming them in Unpair's question ("Your Chrome" 3 and 4).
  planque's grant read names each connection's Chrome; they wait on tafs' words for those lines, as on Linux.
