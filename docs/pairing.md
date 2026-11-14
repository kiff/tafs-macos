# Signing in and adding this Mac

How a Mac gets a session with KIFF, and how it gets the right to ask for approvals. The
contract is KIFF's `docs/desktop-client.md` (§1.1 and §5). The keys are in
[signing.md](signing.md).

## Two ways in

| | When | What the Mac gets |
|---|---|---|
| **Sign in in the browser** | The account's first device, or to look without approving | A session. On an account that already has a device that approves, it is **view-only**. |
| **Add this Mac with a phone** | The account already has a device that approves | A session that may ask for approvals, once that phone has signed this Mac's keys. |

A code typed from an authenticator app only ever signs in. It never adds a Mac for approvals
and never approves an action.

## Signing in (`KIFFClient.startSignIn`, `token`)

1. The Mac sends its device key's public half, its name, `platform: macos`, and how it
   approves: its approval key's public half, or `approval: passkey` when it has none.
2. KIFF answers a code and a page. The person opens the page, checks the code and approves.
3. The Mac asks for its session every few seconds (`Waiting.until`) until it is handed over.

## Adding this Mac with a phone (`PairingPayload`, `KIFFClient.claimPairing`)

1. The Mac shows a QR code with its public keys and name, and a 6-character check code.
2. The phone scans it, shows the same check code, and signs the Mac's keys behind the
   person's fingerprint or face.
3. The Mac asks for its session with a proof that it holds the device key the phone approved.

A code lasts at most 5 minutes. A session is handed over once.

## Waiting

`Waiting.until` paces every ask as the contract says:

- it waits one interval before the first ask, and between asks;
- "not yet" asks again; "slow down" adds 5 seconds to the interval for the rest of the wait;
- it stops at the code's expiry, and never waits more than 10 minutes;
- any other answer ends the wait and is shown to the person.

## What is never kept or shown

- The session's token is kept in the Keychain only.
- No request, answer, token or signature is logged.
- `NetworkTransport` sends to `https://api.kiff.dev` only, and refuses any other host.

## Tests

`scripts/test.sh pairing`: the exact fields each route is sent, that a Mac with no approval
key never sends one, every answer the contract names, and the waiting's pace with a clock
the test controls. No test reaches the network.
