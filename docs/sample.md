# The sample ("Try it with sample data")

As the iPad's `startSample` and `loadSample` (`AppModel.swift:3004-3018, 6763-6790`) and Windows'
`--sample`: the app opened on sample data, which reads no one's account. The welcome's
**Try it with sample data** (`sample.try_it`), under Continue, opens it. Account's
**Clear the sample** (`settings.clear_sample`) leaves it, back to the welcome. Nothing of it is
kept between launches.

## What it is

This Mac's screens read only tafs cloud and KIFF. So the sample is one transport,
`SampleTransport` (`Core/shell/Sample.swift`), that answers those reads in memory. The window is
the signed-in one, unchanged: no screen has a second path for the sample. Every word is the
iPad's own, from the shared strings (`sample.*`).

- **Home:** the iPad's five sample tafs (`TafTemplates`: Support replies, Late parcels, Access,
  Deploys, Lead follow-up), each working, with its Card (a count a day, held for you, or never),
  and how many of its calls wait.
- **Needs you:** the calls the first two rounds made that a Card holds for its owner (the iPad's
  two `playNextDemoActions()`): Support replies' promise, the reship, the migration, with their
  next steps where the iPad has one.
- **Record**, and a taf's **Activity:** each call of those two rounds, done within its Card or
  waiting for you.
- **Plan & usage:** the iPad's sample balance and both periods' credits (`sampleBalance`,
  `sampleCredits`).
- **A taf's page:** its chat (its hello, and for Support replies the iPad's sample question), its
  Setup (its job as its workflow), and its runs, notes and work, none yet.
- **Account:** Mode reads Sample data (`settings.mode_sample`). The account approves nothing
  (`view`), and its devices, passkeys, groups and members are empty.

## What it never does

- **It reaches no network.** The session has no device key and no security key, so planque's
  reads (which need this Mac's signed proof) and Coach's start never begin, and nothing streams.
  No sample answer names a logo, so the app's one logo reader (`AppLogoImages.app`, tafs cloud's
  `/v1/logos/`) is never asked; a test pins it.
- **It keeps nothing.** The Overview's list last read (`RememberedHome`) isn't kept for the sample.
- **It writes and approves nothing.** Every write is refused with the line that it takes KIFF
  (`sign_in.with_kiff`), and nothing is done. A shared line of its own is asked of tafs's strings.
- **A read it doesn't have** is "not found", said as the screen says any read that failed.

## Not yet

The demo's later rounds (the iPad's pull to play the next), the sample chat's live replies
(`sampleReply`), the sample's devices and alerts, and keeping it between launches (the iPad's
`SampleStore`).
