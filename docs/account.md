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
| `devices()` | `GET /v1/me/devices` | Each device: KIFF's name for it, its platform, its key's fingerprint, when it was last used, and which one is this Mac. |
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

- KIFF's name for it, when it was last used, and its key's fingerprint, which can be selected
  to compare with another device's screen;
- "This device" on this Mac's own row, with no button.

**Signing another device out is an approval**, since it can take away the account's power
to approve. So:

- **A Mac that can't sign an approval draws no Sign out for another device**, and its model
  sends no removal even if asked. It says "This device can't approve. Approve on another
  device signed in to your account." That is every Mac today: the approval key behind Touch
  ID arrives in its own pull request, and turns the button on for the Macs that have it.
- Where the button is drawn, it asks first, naming the device. After a removal the list is
  read again from KIFF. KIFF's refusal for want of an approval shows the same line; any other
  refusal says why and leaves the list as it was.

This Mac is never removed from its own row: it signs out with Sign out, which also forgets
its session.

`scripts/test.sh account` writes `build/screenshots/devices-*.png`.

## The Account page (`AccountView`, `AccountModel`)

To the iPad's layout: a large title and grouped panels of rows.

| Group | Rows |
|---|---|
| Your account | Mode ("Signed in with KIFF"); **KIFF account**, the account's name (else its slug); and **Signed in as**, the email, left out when it is the account's own name. From `GET /v1/me`. |
| View only | **Only when KIFF says this session is `view`** (`approval_mode`): what a view-only Mac does, and **Add this Mac**. A KIFF that doesn't say, and a session it calls `passkey` or `key`, show no such group. |
| People & apps | Devices (opens the list), Connect apps. |
| Plan | Always there. tafs cloud's `plan_line` at 16 semibold in `plan_tone`'s colour (red waiting, amber warning), then "Plan & usage"; just "Plan & usage" when the balance can't be read. It opens Plan & usage. |
| Theme | Light, Dark, or System. Kept for the next launch and applied to the whole app. |
| How it works | The shared line. |
| Legal | Terms and Privacy policy, on kiff.dev. Only those two pages are ever opened from here. In any language but English each says "(in English)", as on the iPad. |
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

Not on the Mac yet: People & groups, Coach's suggestions, Alerts, Language, AI use, Time zone,
Export my chats, About.
