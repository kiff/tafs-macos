# The download: a signed, notarized disk image

tafs for macOS is downloaded as a disk image (`tafs-<version>-<build>.dmg`). A person opens it and drags tafs to Applications. The app inside is the same build as `scripts/build.sh`, for Intel and Apple silicon. It's signed with the team's **Developer ID** under the hardened runtime, **notarized** by Apple, and its ticket is **stapled** to the image, so it opens on a Mac on macOS 12 or later with no warning, even offline.

This page is about packaging only. The app's code is in the rest of the repo.

## Make one

**By hand, from main:** Actions → **DMG** → Run workflow on `main`, then approve it as the `mac-signing` environment's reviewer. The run:

1. builds the app (`scripts/build.sh`);
2. imports the Developer ID certificate into a keychain of its own, which it deletes at the end;
3. signs the app, packs the image and signs it (`scripts/dmg.sh`);
4. sends it to Apple's notary service and waits for its answer, then staples the ticket. If Apple refuses it, the run prints Apple's log and stops;
5. checks the image as Gatekeeper would, prints its SHA-256, and keeps it as the run's **`tafs-dmg`** artifact for 30 days;
6. publishes it as a **GitHub pre-release** of this repo, `v<version>-<build>` (for example `v0.1-1`), with its SHA-256 in the notes. A version already released stops the run, so `App/Info.plist`'s version or build goes up before each new one.

**On a pull request** that changes the packaging (`scripts/dmg.sh`, `scripts/build.sh`, `App/Info.plist` or the workflow), the `check` job builds the image signed ad hoc and opens it, with no secret and no Apple.

**On a Mac, to try the packaging:**

```sh
scripts/build.sh && scripts/dmg.sh            # signed ad hoc: for a check, not for anyone's Mac
```

`dmg.sh` opens the image it made, as a person would, and checks that `tafs.app` and the `Applications` link are there and that the app is still signed.

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
| Where the image is downloaded from | a GitHub pre-release here, for the team (the PM's call). Linking it from kiff.dev/tafs/download for everyone is the owner's yes, later. |
| The version | `App/Info.plist`'s 0.1 (1), as the app has it. |
