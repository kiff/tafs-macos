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
  Deploys, Lead follow-up), each with its Card (a count a day, held for you, or never) and how
  many of its calls wait. Each one's state is as tafs cloud's `stateOf` gives it: waiting while a
  call of its waits for you, else paused once paused in its chat, else working.
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
  (`view`). **Devices** lists the iPad's three (`SampleScreens.devices`): this Mac, an iPhone used
  three hours ago, and a Mac yesterday, each "tafs on …". Its passkeys, groups and members are
  empty.
- **Play the next sample actions** (`sample.play_next`), at the Overview's foot with "Sample
  data. A new taf starts in Coach." (`home.sample_foot`), as the iPad's Home: each taf plays its
  script's next call (`playNextDemoActions()`), up to the last, and every list is read again.
  The scripts are the iPad's whole `TafTemplates`. A call its Card holds for you joins Needs you,
  and one its Card refuses outright (`never`) is in the Record as "refused by its Card", never
  sent: the third round has Deploys' `DROP TABLE sessions_old`.
- **A language chosen in Account** while in the sample: its tafs, calls and devices read in it
  from the next read on, with the rounds played kept. Each request is answered in its
  `Accept-Language`, as tafs cloud and KIFF answer (`SampleTransport.words(for:)`), from the
  app's own strings; one that can't be loaded is answered in the sample's first language.

- **A taf's chat answers**, as the iPad's `sampleReply`: what's sent (`POST …/messages`) is kept
  in memory with the taf's reply, from its own record. That's its last three calls ("Lately: …"),
  else "Nothing done yet today.", then how many of its calls wait in Needs you, then the
  sample's note (`sample.reply.*`). "stop", "pause" or "hold off" pauses the taf on Home, and
  "go", "carry on", "resume" or "continue" brings it back. "more", "raise", "limit", "bigger" or
  "increase" says only its Card can give it room. Support replies' sample question has its
  answer too, as on the iPad. Cleared with the sample.

## What it never does

- **It reaches no network.** The session has no device key and no security key, so planque's
  reads (which need this Mac's signed proof) and Coach's start never begin, and nothing streams.
  No sample answer names a logo, so the app's one logo reader (`AppLogoImages.app`, tafs cloud's
  `/v1/logos/`) is never asked; a test pins it.
- **It keeps only itself, as the iPad's `SampleStore`.** What changed in it (the rounds played,
  what was said in each taf's chat, the tafs paused) is one local file, `tafs/sample.json` in
  Application Support (`SampleStore`). The next launch with no one signed in opens the sample
  where it was left; a file that doesn't read is as new, and one can't add rounds past the
  scripts or a taf that isn't the sample's. Clear the sample removes it, and so does a sign-in.
  The Overview's list last read (`RememberedHome`) isn't kept for the sample.
- **It alerts for nothing.** Its held calls are no one's, so the window never announces them, and
  Account › Alerts' Turn on says it takes KIFF, without asking macOS or saving a choice.
- **It writes and approves nothing.** Every write is refused with the shared line, "This isn't in
  the sample. Sign in with KIFF to do it." (`sample.not_in_sample`), and nothing is done.
- **A read it doesn't have** is "not found", said as the screen says any read that failed.

## Not yet

The iPad's local alerts for the sample's held calls: the Mac's sample announces nothing, and turning
alerts on in it says it takes KIFF.
