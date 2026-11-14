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
