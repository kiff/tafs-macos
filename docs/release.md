# The download: a signed, notarized disk image

tafs for macOS is downloaded as a disk image (`tafs-<version>-<build>.dmg`). A person opens it and drags tafs to Applications. The app inside is the same build as `scripts/build.sh`, for Intel and Apple silicon. It's signed with the team's **Developer ID** under the hardened runtime, **notarized** by Apple, and its ticket is **stapled** to the image, so it opens on a Mac on macOS 12 or later with no warning, even offline.

This page is about packaging only. The app's code is in the rest of the repo.

## Make one

**By hand, from main:** Actions → **DMG** → Run workflow on `main`, then approve it as the `mac-signing` environment's reviewer. The run:

1. builds the app (`scripts/build.sh`);
2. imports the Developer ID certificate into a keychain of its own, which it deletes at the end;
3. signs the app, packs the image and signs it (`scripts/dmg.sh`);
4. sends it to Apple's notary service and waits for its answer, then staples the ticket. If Apple refuses it, the run prints Apple's log and stops;
5. checks the image as Gatekeeper would and prints its SHA-256. It isn't kept as a run artifact: this repository is public, so any signed-in GitHub user could download a run's artifacts, and the draft release is the image's only copy;
6. attaches it to a **draft GitHub release** of this repo, `v<version>-<build>` (for example `v0.1-1`), with its SHA-256 in the notes. A draft is seen only by people with push access; publishing it is a separate, deliberate step. A version already released stops the run, so `App/Info.plist`'s version or build goes up before each new one. Its notes are `release-notes/v<version>-<build>.md`, in 8 languages: they're pasted into the draft by hand, under the SHA-256 line the run writes.

**On a pull request** that changes the packaging (`scripts/dmg.sh`, `scripts/build.sh`, `App/Info.plist` or the workflow), the `check` job builds the image signed ad hoc and opens it, with no secret and no Apple.

**On a Mac, to try the packaging:**

```sh
scripts/build.sh && scripts/dmg.sh            # signed ad hoc: for a check, not for anyone's Mac
```

`dmg.sh` signs the app with `App/tafs.entitlements`, which holds only the microphone (`com.apple.security.device.audio-input`) and the camera (`com.apple.security.device.camera`): under the hardened runtime, dictation needs the first and Take photo the second. It prints the app's entitlements and stops if either is missing. It then opens the image it made, as a person would, and checks that `tafs.app` and the `Applications` link are there and that the app is still signed.

## What approving a signing run unlocks, and what it doesn't

The `mac-signing` approval (its required reviewer) is what turns a run into a signed, notarized draft. Then the owner publishes the draft.

**It unlocks:**
- **A download that opens with no warning** on macOS 12, even offline: Developer ID, the hardened runtime, notarized and stapled.
- **One Keychain identity across builds.** Each unsigned build is a new app to the Keychain, so an earlier build's session and keys may refuse to change ([pairing.md](pairing.md), The Keychain). Builds signed by the same team are the same app, so an update keeps the session and needs no new pairing.

**It doesn't unlock, by itself: alerts with tafs closed.** Three of the four Partial rows in the port checklist wait on that: Needs you's and Account › Alerts' "even with tafs closed" (with `AlertingTafsView`), and the brief's alert routing by `brief_kind`. The fourth, the sample's alerts, is left out by design and isn't push. Today an alert comes only while tafs is open (`approvals/Notifier.swift`). A push with the app closed comes through Apple's push service, which needs, beyond the signature:
1. the push capability on the app's identifier, `bot.tafs.macos`, at developer.apple.com;
2. a Developer ID provisioning profile with it, embedded in the app;
3. `com.apple.developer.aps-environment` in `App/tafs.entitlements`, which today asks for the microphone and the camera only;
4. the app registering for remote notifications and sending its token to tafs cloud, and tafs cloud sending to a Mac's token.

Steps 1 and 2 are done at developer.apple.com: `bot.tafs.macos` has Push Notifications, with a Developer ID profile for each of the team's Developer ID Application certificates. The release fetches the right one itself (`push` ticked on the DMG workflow): `scripts/push-profile.swift` lists the account's active Developer ID profiles with the App Store Connect key notarization already uses, and keeps the one whose certificates include the one the app is signed with and whose entitlements give `aps-environment` production to `R54YWFRK4B.bot.tafs.macos`. If there isn't exactly one, the run stops. No profile is kept in this repository or in a secret, and the run removes it with the key. Steps 3 and 4 are written, and built only with `PUSH=1`:
- `PUSH=1 scripts/build.sh` compiles them in (`-D PUSH`). The app asks AppKit for its push token (`PushToken`). Turning Alerts on this Mac on points KIFF's held-call alerts at tafs cloud (`POST /v1/me/alert-targets`, signed by the device key) and gives tafs cloud the token with that target's secret and the kinds chosen: `POST /v1/push` with `platform: macos`, `environment: production` and its sound. When alerts are turned off, or at sign-out, it takes the token back with `DELETE /v1/push/{token}` (`MacPush`, `AlertsModel`).
- KIFF's alert target is asked for only by someone who answers held calls, since it replaces the account's; anyone else registers for their own kinds without it. It's signed by the device key with no prompt, where the iPad asks Face ID first. That's deliberate: the call grants nothing, its address is fixed, and its secret goes only to tafs cloud.
- Push syncs run one at a time, so a register still on its way can't land after a take-back. While alerts are on, the token is registered again at each launch, and again when tafs cloud says it doesn't alert this Mac.
- At sign-out, the token is taken back while the session still reads. That includes a token this Mac has but never kept, since a register whose answer was lost still left a row. It's tried three times, a second and three seconds apart; a 401 counts as failed. If it still fails, sign-out stops before KIFF is asked, with `alert.still_on_after_sign_out`: Try again, Sign out anyway, or Cancel.
- With them come the three rows' screens: Needs you's `AlertsCard`; Account › Alerts' "What alerts you", read with the token (`GET /v1/push`), with the tafs that alert (`AlertingTafs`); and where a clicked alert opens, `brief_kind` included (`MacPush.destination`).
- `PUSH=1 PROFILE=… IDENTITY=… scripts/dmg.sh` embeds the profile as `Contents/embedded.provisionprofile` and signs with `App/tafs-push.entitlements`: the usual two, plus `aps-environment`, the app's identifier and its team. Without `PUSH=1` the script refuses an app that carries `aps-environment` or a profile, since macOS won't launch a restricted entitlement without the profile that allows it.
- tafs cloud takes `platform: macos` and sends it with the topic `bot.tafs.macos` (kiff/tafs#1961).

The DMG workflow doesn't set `PUSH`, so a release is built as before. Until all four steps are done and a signed build gets an alert with tafs closed, those three rows stay Partial, and this app never says alerts come with tafs closed.

## The secrets

All are secrets of kiff/tafs-macos's **`mac-signing` environment**, never repository secrets. Any workflow on any branch that someone with write access pushes can read a repository secret, and a leaked Developer ID certificate signs software that Macs trust as ours. The environment allows `main` only and asks its reviewer before each run, so only the DMG workflow's `release` job and the certificate workflow read them, run from main and approved:

| Secret | What it is | Made by |
|---|---|---|
| `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD` | the Developer ID Application certificate and its key, as a .p12 (base64), and its password | the certificate workflow, below |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | an App Store Connect API key, which the notary service accepts | the same key as kiff/tafs's, stored here too, in the environment (`gh secret set NAME --env mac-signing -R kiff/tafs-macos`) |

A run without them stops at once and names the ones missing.

## The certificate, once

The **Developer ID certificate** workflow makes the certificate. It's kiff/tafs's Mac installer certificate workflow (`docs/mac-app.md` there), for the Developer ID type. Its private key is made inside the run and leaves it only encrypted to an admin's public key. This repository is public, so its logs and artifacts are too. An admin does each step, on their own machine:

0. **The `mac-signing` environment comes first** (kiff/tafs-macos → Settings → Environments), with a required reviewer and deployment branches limited to `main`.
1. **Make an RSA key pair,** and keep its private half there:

   ```bash
   openssl genrsa -out developer-id-signing.pem 4096
   openssl rsa -in developer-id-signing.pem -pubout | base64 | tr -d '\n'
   ```

2. **Run "Developer ID certificate"** from main, with that line as `public_key`, and approve it. The run prints the certificate's id and expiry only.
3. **Decrypt the artifact and store the two secrets:**

   ```bash
   gh run download <run id> -R kiff/tafs-macos -n developer-id-sealed -D sealed
   openssl pkeyutl -decrypt -inkey developer-id-signing.pem -in sealed/developer-id.key.enc -out aes.key \
     -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in sealed/developer-id.tar.enc -out bundle.tar -pass file:aes.key
   mkdir out && tar -C out -xf bundle.tar
   base64 < out/developer-id.p12 | tr -d '\n' | gh secret set DEVELOPER_ID_P12 --env mac-signing -R kiff/tafs-macos
   tr -d '\n' < out/password.txt | gh secret set DEVELOPER_ID_P12_PASSWORD --env mac-signing -R kiff/tafs-macos
   ```

4. **Delete the run's artifact** and the local files: `sealed`, `aes.key`, `bundle.tar`, `out` and, once the secrets are stored, `developer-id-signing.pem`.

**If Apple refuses the certificate** to the API key (a Developer ID certificate may need the Account Holder), the run fails with Apple's words and makes nothing. The Account Holder then makes a Developer ID Application certificate at developer.apple.com (Certificates → +) on their own Mac, exports it with its key as a .p12 from Keychain Access, and stores the two secrets as in step 3.

If anything readable ever reaches a log, revoke the certificate at once (developer.apple.com → Certificates) and make a new one.

## Not done yet

| What | State |
|---|---|
| **The first signed, notarized image** | **owed:** after the secrets are stored. Then it's installed on a Mac on macOS 12 to check it opens with no warning. |
| Where the image is downloaded from | a draft release here, for the team. Publishing it, and linking it from kiff.dev/tafs/download for everyone, come later. |
| The version | `App/Info.plist`'s 0.1 (5). Build 1 was the first draft, signed with a personal Developer ID; build 2 is the first signed with the company's; build 3 carries the macOS 12 fixes (#139); build 4 adds the app's icon; build 5 is the next draft, with its notes in `release-notes/v0.1-5.md`. |
