# A taf's page

A taf opens from the sidebar to its own page, as on the iPad. This page describes what the
page reads, then how it is drawn.

## A taf's Cards (`TafCard`, read with `Home`)

tafs cloud sends each taf's Cards with the list (`GET /v1/home`, `tafs[].card.cards`). A
**Card** is what KIFF lets the taf do on its own, and how much of it is left. The app reads it
and works out one thing only: what is left, as KIFF's limit less what KIFF says was used.

| Read | From | What |
|---|---|---|
| Its id at tafs cloud | `tafs[].id` | Nil for an agent tafs doesn't run. |
| Each Card | `id`, `title`, `active`, `expires` | A Card with no id or title is left out, never the taf. |
| Each thing it lets the taf do | `rules[]`: `label`, `outside`, `per_action`, `per_window`, `extra_room`, `base_limit`, `count_per_window`, `window_words` | KIFF's words for it; `refuse` or `hold` for a call outside it (any other word is unknown, and nothing is said about it); its limit and tafs cloud's words for the window. A Card may have no rules. |
| Its money | `total`: `limit` and `used`, each `{minor, unit, scale}`, and `window_words.now` | |
| Its calls | `calls`: `limit`, `used`, and `window_words.now` | |

- **The figure** (`TafCard.figure`) is what is left: of the money when the Card has a money
  total, of its calls only when it has none. Never below zero. A money Card whose money use
  can't be read has no figure, never its calls in its place.
- **No figure is ever a guess.** With no `used` (KIFF couldn't read it), or a limit and a
  used in different units or scales, there is no figure.
- **Money** is written as the app's language writes it (`Amount.written`): "€1,960",
  "€12.50". Whole amounts lose their zeros, as the apps write money everywhere. A unit that
  isn't a currency's code follows the number as written.

## The page (`TafView`)

A taf in the sidebar opens its page in place of the screen, as on the iPad. The open taf sits
on the chosen row's grey; no screen row is the chosen one while it is open. Choosing anything in the
sidebar, the screen already open too, closes it. An agent tafs doesn't run (no `id`) has no
page. Coach's **Open** on a hand-over opens the taf it made, when the list has it, else the
Overview.

| Part | What |
|---|---|
| The head | As the iPad's: the taf's 34-point avatar (`TafAvatar`), its name in 20 rounded bold, and at the right **tafs cloud's state as the iPad's chip** (`TafState.chip`): Working (green), Waiting (amber), Ready for `idle`, Paused (soft), Stopped or Halted (red), each the shared `taf.state.*` line on its tone at 15%. No chip for a word this app doesn't know, nor for a working taf that needs the person: its Activity says what went wrong. |
| Its version | Under the head, for whoever manages the taf, as the iPad's `versionLine`: "Version 3 · live" (else "Versions"), which opens its versions (`GET /v1/tafs/{id}/versions`, `TafVersions`) newest first: each one's number, Live now, what changed, who made it and when ("brings a new Card" while its Card waits), and what each ended trial came to ("Tried 2 Nov · 3 calls, 1 held · went back"); "One version so far" while the list is empty (kiff/agents records version 1 once a second is made). The sheet opens on the iPad's line about trying a version first, and reads the versions again. A switch under way says the taf doesn't run until it's finished or cancelled, with **Cancel** (`DELETE /v1/tafs/{id}/switching`, unsigned, then the versions are read again; "The switch wasn't cancelled. {why}" when refused). A read that fails keeps the versions already read and says "Its versions couldn't be loaded. {why}" in red under them; the spinner shows only with neither. The reader is the iPad's: a trial needs its `ended`, a switch its `at`, and `by` is words. Installing, finishing a switch and trying a version are signed by the phone: this Mac lists them only. An open trial ("Trying" on its row, the header's resume link, `loadTrial`) comes with the trials, whose chat isn't on the Mac yet. The time under each version is in this Mac's time zone until the account's zone is read (the iPad's `shown` uses the account's). No fixture for it in kiff/tafs's `contracts/` yet: the shape is the iPad's reader. |
| Who it's shared with | Under its version, for whoever manages the taf, as the iPad's `ShareLine` (`ShareViews.swift:6-63`, `TafDetailView.swift:183-190`): one line, 14 in the soft colour, from KIFF's grants (`GET /v1/agents/{agent}/grants`) named by the account's groups and people. KIFF's default group alone is "Shared with everyone"; otherwise each group by its name and each person by their email, never the person reading ("Not shared" when only they use it); "Sharing…" until it's read. It's read again whenever the groups change, and People is read first when neither groups nor people are. **Share is signed with Face ID on the iPad** (`ShareTafSheet`), which this Mac can't do, so there's no Share button here: share from a device that can approve. |
| The tabs | **Chat**, **Activity**, **Card** and **Setup**, in the iPad's order, as its switch. |
| Chat | The taf's own conversation (`GET /v1/tafs/{id}/conversation`), drawn as Coach's is, with no title of its own. Its box says "Message {taf}", and "Write the next message" while the taf works. Its Cards are beside it in the iPad's 360-wide column, as the wallet stack below, under "Card" or "Cards" (`card.heading`, by how many), with a button to all its Cards. tafs cloud is never asked which taf is Coach. |
| Card | The Cards as the iPad's wallet (`CardStack`): the furthest back on top, each a band of 26 points above the one in front and a shade darker, the live one in front until another is clicked; the panel under them is the front Card's. Each face in the taf's colour, a payment card's shape (85.6 by 54) at most 300 wide, as the iPad's: its title, the figure, the first limit for each call ("up to €150 each; more asks you first"), how many tools past one ("no actions yet" with none), and "Until {date}", "Ends · No end date", or "Ended" for a Card no longer active, which is faded. Then a panel of what it lets the taf do: KIFF's label, what happens outside it, and **its limits as the iPad's `CardRule.summary`** (`TafCard.Rule.summary`): each call's, the Card's own total for its window (`base_limit`), the extra room apart, and its calls. The room is apart only beside `base_limit`: without it, `per_window` already holds the room and is said once. **A Card with no rules has no panel**, never an empty one. With no Card, nothing is said: tafs cloud sends no field that says one was revoked. |

- Every word from KIFF or tafs cloud (a name, a title, a label, a window) is drawn as sent,
  with `Text(verbatim:)`.

## Activity and Setup (`TafActivity`, `TafSetup`, `TafPagesModel`)

Both are read when their tab opens, from tafs cloud's routes, and **only read**: nothing is
changed from either tab. The shapes are tafs cloud's contracts, `contracts/taf-activity.json`
and `taf-setup.json` in kiff/tafs, read by `scripts/test.sh contracts`.

| Tab | Route | Drawn |
|---|---|---|
| Activity | `GET /v1/tafs/{id}/activity?filter=` | The taf's first Card in one line (below), then what waits on the Card for want of a unit, then **its work**, as the iPad's `TafActivityList.parts`: under "Its work" (`WorkPanel`), **a taf that isn't healthy** as Home reads it (`health`, each line read on its own, the iPad's `HealthLines`): each line, amber when at risk and red when failing, with the fixes tafs cloud decided for it: the credits fix opens Plan & usage; Coach's fix, which on the iPad improves the taf in Coach mode, comes with Coach mode and is no button until then; any other kind is no button. The rest of `WorkPanel` (`GET /v1/tafs/{id}/work`: its summary line, the oldest waiting case, Answer within, skipped firings and requests) isn't here yet, so the panel shows only with a health to say. The Card's line: the taf's first Card in one line ("€1,960 left today of €2,000", its title), which opens the Card tab; then tafs cloud's `filters` as pills, each asked for again with its id; then its calls by day (`groups`, else `entries` as one list): each with its kind's dot as the iPad's (done and approved green; refused, not done and revoked red; held, sending and any other kind amber), its `title`, `detail`, `time`, and `amount_text` under the time; while `next_cursor` is sent, the next page when the list's end shows (`&cursor=`), an untitled first day carrying on the last; and `end_words` under the last page. |
| Setup | `GET /v1/tafs/{id}/setup` | What waits on the Card for want of a unit (`card_unit_exceptions`: title, words, history, edged in amber); tafs cloud's **Connect again** words when the taf's own sign-in expired (`connect_again`, edged in amber); the workflow; under "Connected apps", **one row per app**, as the iPad's `TafPresentationViews.swift` (`ConnectedToolsRing`'s nodes, as a list): connections to the same app are grouped, the one shown is the first with actions (`action_count`), else one to sign in again, else the first; each row its name, `action_words` (green while `running`, else soft) and `status_words` (amber when it must sign in again). A row opens the app's sheet (`ConnectedAppSheet`): its status, what it may do (each action's title, its `limits` and `step_words`), its week (`stats.words`), which opens the taf's Activity with tafs cloud's `stats.activity_query` (sent only as a query; disabled with no actions), and the other sign-ins to the same app. Sign in again and Disconnect wait for approvals; the line for connections that couldn't be read; then the versions, by tafs cloud's `title` and `summary`, and under "What it remembers" the notes' `title` and `latest` note. The connections' line is red, with Try again. Someone who neither uses nor oversees the taf is refused: the tab says it couldn't be read. |

- **Everything is drawn as sent**, with `Text(verbatim:)`. The app words no call, no part and
  no filter.
- A call, a day, a filter or an exception that doesn't read is left out, never the tab. An
  Activity with neither `groups` nor `entries`, or a Setup with none of its parts, is
  unreadable.
- **Not yet:** the workflow steps' rows (the contract has none to read them by), the
  Connect again button (a sign-in, on the phone for now), opening an app's week in Activity
  (`stats.activity_query`), the Card-unit exception's "Add a limit" (it goes through Coach, with its approval),
  Forget a note, Pause, and asking again with the `revision` as `If-None-Match`.

## Halt (`Halt`, `HaltModel`, `HaltRow`, `HaltView`)

Ported from the iPad's `HaltScreen.swift` (`HaltScreen`, `HoldRow`, `HaltRow`) and
`TafsCloud.Halt`. There is no fixture for it in kiff/tafs's `contracts/` yet: the shape is the
iPad's reader.

- **Where, and for whom,** as the iPad's: a taf's own halt is the first row of its Setup, only
  for whoever manages the taf as KIFF says (`GET /v1/me/access`, `Access.manages`; nothing until
  that is read) and not for a taf whose Card is no longer active. KIFF's access is read with
  every read of the tafs, once the list has read, as the iPad's `refresh()`; a read that fails
  keeps what was read. Each of `use`, `oversee` and `manage` must be there as a Bool, as the
  iPad's `Access`: one missing fails the whole read. Every taf's is a row on the
  Overview, only for whoever manages the account's Cards (`Me.managesCards`: `cards.manage`, or
  KIFF doesn't say), while a taf runs, and also with no taf while the account is halted, where
  it is resumed from. (tafs cloud's Setup answers anyone who uses or oversees the taf, so the
  Setup alone says nothing about halting it.)
- **Read:** `GET /v1/tafs/{id}/halt`, or `GET /v1/halt` for every taf, when the row shows.
- **Halt now** (Halt all now): `POST`, one click with no key, since it only takes authority
  away. Then it is read again every 2 seconds while halting, for up to 2 minutes. Halt again
  asks a part that didn't take it the first time.
- **The screen:** the taf's name (or "All your tafs") over Running, Halting… or Halted, and
  what halting does, or since when it holds; once halting, who holds it: no run starts
  (kiff/agents), KIFF refuses its calls, the connection sends nothing (planque), each Done or
  Waiting. A taf halted with the whole account says so.
- **Resuming gives authority back**, so it is signed. Until this Mac can sign it, where the
  iPad has Resume it shows the iPad's line for an approval that can't be made here
  (`approval.device_can_not_approve_approve`, `Biometry.short`): approve on another device,
  which for most people is their phone.
- A halt tafs cloud refuses says why, in the shared words with the refusal's why (see
  [shared.md](shared.md): its words, else its error, else "tafs cloud answered {status}"), and
  stays as it was. A halt it answers reads the list and KIFF's access again at once, still
  busy, so the taf reads halted there too, then is followed while halting.
- The iPad's `stopped` (how many runs a halt stopped) isn't read: no screen shows it.

## Starts when and Results go to: the taf's dial (`Knob`, `TafKnobModel`)

The iPad's knob API as its Setup draws it: `StartsWhenView`, `ResultsGoToView`,
`KnobPendingPanel` and `SizeStepper` (`ios/Tafs/Views/TafSetupViews.swift`), with
`TafsCloud.Knob` (`KIFF/TafsCloud+Knob.swift`) and `loadKnob`, `adjustKnob`, `changeKnob`,
`setResultPlaces`, `removeFollowUp` and `setPaused` (`App/AppModel.swift`). The iPad's round
dial (`TafKnobView`, `TafDialPanel`, `TafKnobRemote`) isn't drawn on its screens today, so it
isn't here either. Both screens open from the taf's Setup, as sheets: Starts when after its
workflow, Results go to after its apps. As on the iPad (`TafDetailView.swift:302-317`), both
rows are offered whenever the taf is tafs cloud's, while its Setup is read or couldn't be too.

- **The dial** is read with `GET /v1/tafs/{id}/knob`. With a change waiting (`pending`), that
  version's is read (`?version=`); one installed meanwhile (404) is read as it is now. A read
  that fails says tafs cloud's words, else its error, else its status (`CloudRefusal.why`, the
  iPad's `CloudError`). Every label and line is tafs cloud's. A stop must have its id, and anything tafs cloud sends must
  be the iPad's type; what it doesn't send takes the iPad's defaults.
- **Starts when:** its schedule (tafs cloud's words, − and + through the sizes it offers,
  when it runs next, and what it does if still working: Skip it or Run after), the app events
  it listens to (Stop, to take one out), the follow-ups it set itself (Remove, with when they
  end), then Pause or Resume every start. Paused is tafs cloud's `status` (the iPad's
  `cloud.paused`), never Home's `state`, which says `waiting` for a paused taf with a call held.
- **Times** are the account's, as the iPad's `AccountTime` (`Components.swift:196-247`): the
  next run as 14:05, a follow-up's end as "16 Nov 2026, 08:00", each with the zone's short name
  when the account's clock isn't this Mac's. A zone this Mac doesn't know is UTC, named as
  macOS names it, as the iPad's (`abbreviation(for:)`): newer systems say "GMT" for it, on the
  iPad too.
- **Results go to:** tafs' own places (Reply to the sender, Alert our phones, Email me), set at
  once (`PUT …/results`), at least one always on; then each place in a connected app, turned
  through the dial's next version.
- **A change to the taf itself** (`PUT …/results`, pause and resume) answers the taf as tafs
  cloud runs it (`{taf}`: its `id`, `name`, `job` and `status` must be there), as the iPad's
  `CloudTaf`. An answer that doesn't read is no change, and says so. The taf it answers is the
  one drawn until Home's next read brings it. After a pause or resume the tafs are also read
  again, so the sidebar and the Overview say it: the iPad sets its own list's state instead.
- **A change** copies the live `setting`, changes one thing and sends it whole
  (`PUT …/knob`): tafs cloud makes the next version, and nothing runs from it until it goes
  live. Only whoever manages the taf, as KIFF says, gets the controls.
- **Signed, so not on this Mac yet:** making the next version live (the iPad's Make it live
  begins the version switch and signs the taf's Card) and approving an app event (signed with
  the approval key, then subscribed at planque). Where the iPad has their buttons, this Mac
  shows the line for an approval made on another device
  (`approval.device_can_not_approve_approve`).
- **What went wrong** shows in red at the top of the screen, where the iPad says it in its
  error line: the dial that couldn't be read, a change that didn't go, a place or a pause
  tafs cloud refused (its words), or not every start paused (a 502 while pausing). Only the
  dial's own read error is cleared by the next read that works; any other stays, as the
  iPad's `lastErrorFrom`.

Not here yet: its doors (the Doors screens), "Change when it starts with Coach" and "Add a
place from a connected app" (Coach on the taf), and Not sent with Send again (the taf's work).

## Tests

`scripts/test.sh taf`: the Cards as tafs cloud sends them, a Card that doesn't read, a Card
with no rules, the figure from money and from calls, no figure when used is unknown or the
units differ, a used over the limit, money in its language, and each state's chip. On a Mac: a taf's chat reads
that taf's conversation without asking which taf is Coach, a Card with no rules has no panel
under it, and the screenshots `build/screenshots/taf-<tab>-<language>.png`, each tab in three languages.
`scripts/test.sh contracts` reads both contracts; the Mac tests read the Activity and Setup
from them, check every request is a `GET` of that taf, a filter asked for again, and a refused
Setup.
