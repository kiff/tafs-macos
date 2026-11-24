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
| The head | As the iPad's: the taf's 34-point avatar (`TafAvatar`), its name in 20 rounded bold, and at the right **tafs cloud's state as the iPad's chip** (`TafState.chip`): Working (green), Waiting (amber), Ready for `idle`, Paused (soft), Stopped or Halted (red), each the shared `taf.state.*` line on its tone at 15%. No chip for a word this app doesn't know, nor for a working taf that needs the person: its Activity says what went wrong. **The line under the head (its version, who it's shared with) folds away while the chat scrolls down**, as the iPad's `fold`: once the thread has moved 24 points from where it was last marked (`ScrollFold`), down folds it and up brings it back, eased over 0.2 s (none with Reduce motion); a change of tab brings it back. |
| Its version | Under the head, for whoever manages the taf, as the iPad's `versionLine`: "Version 3 · live" (else "Versions"), which opens its versions (`GET /v1/tafs/{id}/versions`, `TafVersions`) newest first: each one's number, Live now, what changed, who made it and when ("brings a new Card" while its Card waits), and what each ended trial came to ("Tried 2 Nov · 3 calls, 1 held · went back"); "One version so far" while the list is empty (kiff/agents records version 1 once a second is made). The sheet opens on the iPad's line about trying a version first, and reads the versions again. A switch under way says the taf doesn't run until it's finished or cancelled, with **Cancel** (`DELETE /v1/tafs/{id}/switching`, unsigned, then the versions are read again; "The switch wasn't cancelled. {why}" when refused). A read that fails keeps the versions already read and says "Its versions couldn't be loaded. {why}" in red under them; the spinner shows only with neither. The reader is the iPad's: a trial needs its `ended`, a switch its `at`, and `by` is words. **Installing a version** (`VersionSwitch`, the iPad's `prepareSwitch` and `useVersion`), forward or back, for someone who isn't view-only on a Mac with its security key: **Install this version** on each version that isn't live (none while a trial is open, one switch at a time), **Finish** on a switch under way, **Stop it and install** when tafs cloud says a run is in the way (`stop_blocking`, with its words for what it stopped), and **Draft its Card again** after KIFF refused a Card as out of date (`card_revised`, `redraft`). tafs cloud begins the switch (`POST …/versions/{n}/switch`, unsigned). A version that brings a Card opens **Its Card** first: KIFF's draft read by this Mac itself, each Card it revises now and after, its new Cards as one, each it removes struck through (`DraftCardsView`, `AccountClient.Draft.shown`), with Cancel (the switch dropped) and Install this version, which confirms that draft on the security key only if it's still the version shown (`KeyAct.confirmDraft`; changed, it's shown again and the switch cancelled). One that brings none, or whose Card KIFF already took, asks the owner's Touch ID or the Mac's password, as the iPad's Face ID. Then tafs cloud makes it live (`POST …/versions/{n}/live`), the versions are read again, and after a new Card the tafs too. A prompt or the key's sheet closed cancels the switch and says nothing; any other failure says why and leaves the switch to finish or cancel, as on the iPad. **Trying a version** (`Trials`, the iPad's `TrialViews`, kiff/tafs#173): **Try it** on a version that isn't live, while no trial is open, on a Mac with its security key. Its sheet reads tafs cloud's draft for the trial (`POST …/versions/{n}/try`) and KIFF's draft itself, then shows the version's note, what trying it means (`version.while_you_try.*`) and its Card's lines. **Start trying** confirms that draft as a trial on the security key (KIFF's draft confirm with `{"as":"trial","version":…}`, the one confirm path a source may name, pinned in `PlanqueRoutesTests`), only if the draft is still the version read (else "what you're asked to approve changed", and it's read again). Only KIFF's `trying` started one (else `version.not_a_trial.*`); then tafs cloud opens it (`PUT …/trial`). **An open trial** (`GET …/trial`) puts its bar over the taf's chat: "Trying version n", not live, **Go back** (KIFF ends the trial Card with the device key's signed call, as it only takes authority away, then `DELETE …/trial`) and **Install** (KIFF's draft confirm on the key if it isn't confirmed yet, then `POST …/trial/install`), each asked first; tafs cloud's guide (what's new, the task to try it with, when it ends unused); and the trial's own chat (`…/trial/conversation`, `…/trial/messages`, text only, never streamed), followed as any chat. Not here yet: the trial's other ways in (the header's link, the menu) and the ended trial's note. The time under each version is in this Mac's time zone until the account's zone is read (the iPad's `shown` uses the account's). No fixture for it in kiff/tafs's `contracts/` yet: the shape is the iPad's reader. |
| Who it's shared with | Under its version, for whoever manages the taf, as the iPad's `ShareLine` (`ShareViews.swift:6-63`, `TafDetailView.swift:183-190`): one line, 14 in the soft colour, from KIFF's grants (`GET /v1/agents/{agent}/grants`) named by the account's groups and people. KIFF's default group alone is "Shared with everyone"; otherwise each group by its name and each person by their email, never the person reading ("Not shared" when only they use it); "Sharing…" until it's read. It's read again whenever the groups change, and People is read first when neither groups nor people are. **Share** is before the line, as the iPad's (`ShareViews.swift:6-45`): the share mark and "Share" (`people.share.action`) in a capsule, 15 semibold. Sharing is signed with Face ID on the iPad (`ShareTafSheet`), which this Mac can't do: a click shows the line for an approval made on another device (`approval.device_can_not_approve_approve`) under it, and nothing is sent. |
| The tabs | **Chat**, **Activity**, **Card** and **Setup**, in the iPad's order, as its switch. |
| Chat | The taf's own conversation (`GET /v1/tafs/{id}/conversation`), drawn as Coach's is, with no title of its own. Its box says "Message {taf}", and "Write the next message" while the taf works. Its Cards are beside it in the iPad's 360-wide column, as the wallet stack below, under "Card" or "Cards" (`card.heading`, by how many), with a button to all its Cards. tafs cloud is never asked which taf is Coach. **A taf's `ask_coach` card** (a card item whose component's `type` is `ask_coach`, with its `text`; `Thread.Card.askCoach`), as the iPad's `AskCoachCardView` (`TafChatView.swift:138-141, 812-826`): the taf's words on a panel, and **Ask Coach** (`coach.ask`) for someone who manages the taf and may use Coach, which opens Coach on the taf with the words in its box, nothing sent (`CoachModel.ask(about:words:mayUseCoach:manages:)`, the iPad's `askCoachAbout`). Anyone else reads the words alone. **tafs cloud's lines around a taf's words**, as the iPad's `RunLine` and `RefusedLines` (`TafChatView.swift:117-129, 553-585`): where a job run's result went, above them (`delivered`: "Sent to Google Sheets · Refunds 2026"); what the run did, counted from the record, under them (`counted`); and a connection its work asked for that was refused (`refused`): the step's words in red, then why and what to do next. Each is drawn as written, small, never folded, and none on the person's message or a run's kickoff; this app counts nothing. **Besides the thread**, as the iPad's `chatItems` (AppModel.swift:6263-6290): KIFF's held calls where the taf made them, while Needs you lists them (`TafChatHeldCard`: its amount, what it is, KIFF's reason, and Needs you's line), gone once answered; what became of the calls the owner answered, from the taf's Record lines (approved, refused, and one the owner approved that wasn't done, is on its way or is unknown), since the chat's first message, in the iPad's words (`chat.outcome.*`); and a door's open knocks (`KnockCard`, as on the Activity). Each is placed among the messages by its time, the thread's own first on a tie (`TafChatTimeline.placed`). A held call is answered in Needs you, with this Mac's security key. |
| Card | The Cards as the iPad's wallet (`CardStack`): the furthest back on top, each a band of 26 points above the one in front and a shade darker, the live one in front until another is clicked; the panel under them is the front Card's. Each face in the taf's colour, a payment card's shape (85.6 by 54) at most 300 wide, as the iPad's: its title, the figure, the first limit for each call ("up to €150 each; more asks you first"), how many tools past one ("no actions yet" with none), and "Until {date}", "Ends · No end date", or "Ended" for a Card no longer active, which is faded. Then a panel of what it lets the taf do: KIFF's label, what happens outside it, and **its limits as the iPad's `CardRule.summary`** (`TafCard.Rule.summary`): each call's, the Card's own total for its window (`base_limit`), the extra room apart, and its calls. The room is apart only beside `base_limit`: without it, `per_window` already holds the room and is said once. **A Card with no rules has no panel**, never an empty one. With no Card, nothing is said: tafs cloud sends no field that says one was revoked. **As the iPad's `card(_:)`** (`TafDetailView.swift:380-462`), above the wallet: tafs cloud's `time_zone_words` (13, soft) and `schedule_time_zone_words` (13, amber), from Home, as sent. **Each face says who issued it** at its bottom left (`TafDetailView.swift:1270-1283`): "Issued by" over "You" for whoever manages the taf, else the account's name, else "The account" (`TafCard.issuer`, the iPad's `issuer(of:)`). Under the panel: **How this is counted** when KIFF sends `counted` for the front Card (each tool's `title` and `lines`; a tool with neither is left out), a sheet of KIFF's lines under each tool's title (`CountedView`); then, for whoever manages the taf, **its halt** (`HaltRow`, below), **its versions** (tafs cloud's Setup `versions.title`, "Changes to how it runs", and its `summary`; the Setup is read here if its tab hasn't been), opening the Versions sheet the header's line opens (`VersionsView`); **Usage**, its credits this period (below); and **Revoke**, on a taf whose Card is live. Revoking is signed on the iPad, which this Mac can't do: Revoke is drawn as the iPad's, in red, and a click shows `approval.device_can_not_approve_approve` under it, sending nothing. Under its rules, as the iPad's (`TafDetailView.swift:420-446`): the front Card's `each_item` totals, one line each; and for a live, active Card (`CardStateLines`), what's pending in KIFF's words, and its `unit_words` with **Reconnect in Coach** for whoever manages the taf. |

- Every word from KIFF or tafs cloud (a name, a title, a label, a window) is drawn as sent,
  with `Text(verbatim:)`.

## Activity and Setup (`TafActivity`, `TafSetup`, `TafPagesModel`)

Both are read when their tab opens, from tafs cloud's routes, and **only read**: nothing is
changed from either tab. The shapes are tafs cloud's contracts, `contracts/taf-activity.json`
and `taf-setup.json` in kiff/tafs, read by `scripts/test.sh contracts`.

| Tab | Route | Drawn |
|---|---|---|
| Activity | `GET /v1/tafs/{id}/activity?filter=` | Its Cards beside it in the page's side column, as on the Chat tab (the iPad's wide page, `TafDetailView.swift:66-72, 121-124, 363-377`), never a bar above it. What waits on the Card for want of a unit, then **its work**, as the iPad's `TafActivityList.parts`: under "Its work" (`WorkPanel`), **a taf that isn't healthy** as Home reads it (`health`, each line read on its own, the iPad's `HealthLines`): each line, amber when at risk and red when failing, with the fixes tafs cloud decided for it: the credits fix opens Plan & usage; Coach's fix, which on the iPad improves the taf in Coach mode, comes with Coach mode and is no button until then; any other kind is no button. **The rest of `WorkPanel`** (`TafWorkPanel`, the iPad's `TafDetailView.swift:604-680`), read from `GET /v1/tafs/{id}/work` when the tab opens (`TafWork`): its summary line (15), left out when it's the health's first reason, so it's said once; its health, the work's own once read, else Home's; its **oldest waiting case** in tafs cloud's words (14, amber and semibold once `late`, else soft); for whoever manages the taf, **Answer within** (the iPad's `PromiseRow`): the promise as tafs cloud keeps it ("4 hours", "1 day", or Not set), a menu of 1, 2, 4, 8, 24, 48 and 168 hours or Not set, sent as `PUT …/promise` with `{"hours": n}` or `{"hours": null}`, then the work read again, and the line "You're told when a case waits longer." (12, dim); then its requests and skipped firings, newest first: a request's line (14; amber when `needs_you`, red when `failed`, else soft), what it used (`credits.words`, 12, dim), and where its result went (12; amber when it can be sent again), with **Send again** for whoever manages the taf (`POST …/requests/{run}/deliveries/{place}/send`: the door's reply, or the place's own key), "Sending again…" while it goes, then the work read again; a skipped firing's words (13, dim). What went wrong (the read, the promise, Send again) is one red line under it, with tafs cloud's why. The panel shows once the work is read, or with a health Home read. **A request that waits on a step its taf handed the owner** (`your_step`) shows that step's card in place of its line, as the iPad's `WorkPanel.request`: Needs you's own `YourStepCard`, Home's copy when Home lists it (it carries the vendor's link when tafs cloud vouched for it), else the request's own; Done and Skip are Needs you's, confirmed and signed by the device key, and the lists are read again after. A step answered or ended here goes back to the request's line at once (the iPad's `canAnswer(step:)`). A `your_step` that doesn't read is none, never the request. Then **its runs** and **the runs it kept** (below). Then tafs cloud's `filters` as pills, each asked for again with its id; then its calls by day (`groups`, else `entries` as one list), each day's title ("Today") as the iPad's, 12 semibold in the dim colour, never in capitals; each call a plain row, not boxed, as the iPad's `SourceActivityRow` (`TafPresentationViews.swift:328-363`): its `title` (15 semibold), `detail` (13, soft), `time` (12, dim), and `amount_text` under the time; **a call opens its sheet** (the iPad's `SourceActivityRow`): the Record's own `ReceiptSheet`, its receipt read from KIFF and checked on this Mac, whenever KIFF's `call` names its taf (`actor_id`, the iPad's `evidence`), receipt or not; the entry is read as the Record's line for this taf (tafs cloud sends the same fields and `call`, with no `taf`), and one that doesn't read stays a row that opens nothing; **a not-done call's next step** (`next`, the iPad's `NextStepRow`, kiff/tafs#476): tafs cloud's `words` as a button for whoever manages the taf: `reconnect` opens Connect apps (signing in again is the phone's on macOS 12), `ask_coach` puts its `message` (else the row's title and detail) in Coach's box on this taf, for someone who may use Coach, with nothing sent; anyone else, and any other kind, reads the words alone, and a `next` that doesn't read is none, never the row; while `next_cursor` is sent, the next page when the list's end shows (`&cursor=`), an untitled first day carrying on the last; and `end_words` under the last page. |
| Setup | `GET /v1/tafs/{id}/setup` | **In the iPad's order** (`TafDetailView.swift:305-358`): what waits on the Card for want of a unit (`card_unit_exceptions`: title, words, history, edged in amber); tafs cloud's **Connect again** when the taf's own sign-in expired (`connect_again`, edged in amber, as the iPad's `ConnectAgainPanel`), for whoever manages the taf and only with its connection, title and words (`usable`): its words in amber, then its button by tafs cloud's title. Connecting again is a sign-in, which grants access and is never done from this Mac, so the button says to approve on another device and sends nothing, as Sign in again does in Connect apps (`GatedAction`); **THE JOB**, its job in words (Home's `job_summary`, else "Works under {count} KIFF Cards." for the live ones, `Home.Taf.job`), with **Improve in Coach** for someone who manages the taf and may use Coach, a new conversation in Coach on the taf (`CoachModel.improve`); **Starts when**; **Connected apps as the iPad's ring** (`ConnectedToolsRing`, `TafPresentationViews.swift:25-143`): the taf's avatar in the middle, which says its job, each app a node around it from the top, clockwise, on a dashed spoke, its name and `action_words` (green while `running`, else soft), with a green arc on the ones it's using now, and **+** (`connect.connect_an_app`), for whoever manages the taf, which opens Connect apps; connections to the same app are one node, the one shown the first with actions (`action_count`), else one to sign in again, else the first. A node opens the app's sheet (`ConnectedAppSheet`): its status (amber when it must sign in again), what it may do (each action's title, its `limits` and `step_words`), its week (`stats.words`), which opens the taf's Activity with tafs cloud's `stats.activity_query` (sent only as a query; disabled with no actions), and the other sign-ins to the same app. Sign in again and Disconnect wait for approvals. Under the ring, **its workflow** inside the panel, by tafs cloud's `title` and `summary`, opening to **Change the workflow with Coach** for whoever may improve it. The Setup that couldn't be read, and the connections' line, are red in the panel, with Try again. Then **Results go to**; **WHAT IT REMEMBERS** (`MemorySummaryPanel`): tafs cloud's count of the notes ("3 notes"), the `latest` note, and **See all** (below). **Remove for good** (`setup.remove_for_good`), drawn as the iPad's for whoever manages the taf (`TafDetailView.swift:354-358`, not behind its `ApprovalGate`). It's signed with the approval key on the iPad (`removeTaf`), which this Mac can't sign, so a click shows the line for an approval made on another device and sends nothing, as Revoke and Share do. Its halt is on the Card tab, as on the iPad. Its doors are in Starts when, as on the iPad. Someone who neither uses nor oversees the taf is refused: the panel says it couldn't be read. **Read with this device's planque proof** (`Planque-Device-Signature`, the iPad's `loadTafSetup` and `grantsReadProof`): the account's tenant, this device's id from KIFF's Devices list (`this_device`, `dev_…`, read once per session), and the device key's signature over planque's `planque.request.v1` message, made with no prompt since it only reads. tafs cloud forwards it to planque, which lists the taf's connected apps. With no device or no key, Setup is read without it and tafs cloud says so where the apps would be. |

- **Everything is drawn as sent**, with `Text(verbatim:)`. The app words no call, no part and
  no filter.
- A call, a day, a filter or an exception that doesn't read is left out, never the tab. An
  Activity with neither `groups` nor `entries`, or a Setup with none of its parts, is
  unreadable.
- **Not yet:** the workflow steps' rows (the contract has none to read them by), the
  Card-unit exception's "Add a
  limit" (it goes through Coach, with its approval), a call's receipt and next step from its
  row, and asking again with the `revision` as `If-None-Match`.

## Usage and what it remembers (`TafCredits`, `TafCreditsModel`, `TafMemory`, `TafMemoryModel`)

- **Usage**, on the Card tab for whoever manages the taf, opens its credits this period as the
  iPad's `TafCreditsView` (`CreditsViews.swift:103-180`) in a sheet: tafs cloud's words for its
  credits, then its runs newest first (`GET /v1/usage/credits/tafs/{id}`), each its `words`
  (semibold and ink when counted, soft when not) and when it ended; **More runs** reads the
  next page (`?after=`) and adds it after the runs read, a run already read not twice. A read
  that fails keeps what was read and says tafs cloud's words, else "{what} couldn't be read:
  {why}"; with nothing read, "These runs couldn't be read." A tafs cloud without the read
  (404) shows nothing. A run tafs cloud says opens (`opens`) has a chevron and opens itself (below).
- **See all**, under What it remembers, opens every note (`GET /v1/tafs/{id}/memory?all=true`)
  as the iPad's `MemoryPanel` (`TafDetailView.swift:1132-1181`): each note's words, its name
  from its path ("customers · acme") and when it changed, and **Forget**, confirmed first
  (`taf.memory.forget_title`, `forget_body`): it goes from the list at once (`DELETE …/memory/{note}`,
  unsigned, as the iPad's), comes back where it was if tafs cloud refuses ("It wasn't
  forgotten. {why}"), and one already gone (404) stays gone. Closing it reads the Setup again,
  so the count is tafs cloud's.

## Runs (`TafRuns`, `RunsPanel`, `RetainedRuns`)

As the iPad's `RunsPanel` and `RetainedRuns` (`TafDetailView.swift:476-517`,
`TafPresentationViews.swift:421-474`), drawn on the Activity after its health, in the iPad's
order (`TafActivityList.parts`):

- **Runs:** a taf that works from its chat says so (`taf.works_from_chat`). Any other says
  Paused (tafs cloud's `status`, as the iPad's `cloud.paused`: never Home's `state`, which
  says `waiting` for a paused taf with a call held), else tafs cloud's `next_run_words`, else
  "Next run at 14:05", else On its schedule;
  then **Run now** (`POST /v1/tafs/{id}/run`, unsigned: it acts within the taf's Card). One
  click sends one request ("Starting a run…" until it answers). A run it started reads the
  runs again; one it didn't start shows tafs cloud's words. A refusal for want of credits shows
  tafs cloud's words; any other says the run didn't start, and why. On the iPad that line is
  the app-wide error; here it sits under the button. Run now is kept by taf for the whole app
  (`RunNowModel`, the iPad's `runsInFlight` and `runNowWords`), so a page opened again still
  knows a run is on its way, and what tafs cloud said.
- **The runs it kept** (`GET /v1/tafs/{id}/work/runs?limit=3`): tafs cloud's heading, each run's
  line with what it used (`credits.words`) and where its result went (each delivery's line),
  and on the first page the firings that started no run, dim, each in its place by time.
  tafs cloud's "see all" line opens all of them in a sheet, twenty a page, each next page read
  as the list's end shows, and `end_words` under the last. The panel is asked again with its
  `ETag` (`If-None-Match`): a 304 keeps what was read. A read that fails says why, with Try again.
  That read alone skips the network's cache (`NetworkTransport.exchange`), as the iPad's
  `representation`; every other request keeps the session's own cache policy.
- The page's `title` and `more_title` are needed, as are each run's `id` and `at`, and each
  skipped firing's `due`, `why` and `words`: without one the page doesn't read. A run's other
  fields that can't be read are none.
- **A run opened** (`TafRunModel`, `TafRunSheet`, the iPad's `KnobRequestDetail`), from the runs
  it kept and from its Usage: `GET /v1/tafs/{id}/requests/{run}` (`TafRequest`), read when it
  opens. It shows tafs cloud's heading (`from`) and line, then each step with its mark (done
  green, next a clock, any other amber) and its line, as sent. For whoever manages the taf: Send
  again ("Try the reply now") for each delivery that offers it (`send_again`), then the run read
  again; and Ask Coach for someone who may use Coach, opening Coach on this taf. Each field is
  needed, as the iPad's reader: a run that doesn't read whole says why, with Try again, and a
  refusal says tafs cloud's words.

## Halt (`Halt`, `HaltModel`, `HaltRow`, `HaltView`)

Ported from the iPad's `HaltScreen.swift` (`HaltScreen`, `HoldRow`, `HaltRow`) and
`TafsCloud.Halt`. There is no fixture for it in kiff/tafs's `contracts/` yet: the shape is the
iPad's reader.

- **Where, and for whom,** as the iPad's: a taf's own halt is a row of its Card tab, after How this is counted, only
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
  each filling its third of the row as the iPad's, when it runs next, and what it does if still
  working: Skip it or Run after), the app events it listens to (Stop, to take one out; one waiting for approval shows its whole filters as sent,
  pretty-printed, as the iPad's `AppEventApprovalSheet`, then says to approve on another device: approving signs planque's
  trigger, a route this Mac never signs), its
  doors for whoever manages the taf (the Doors list, below, as the iPad's
  `TafSetupViews.swift:26-45`), the follow-ups it set itself (Remove, with when they end), then
  **Change when it starts with Coach** for someone who manages the taf and may use Coach (the
  sheet closes, and Coach opens on a new conversation about the taf), then Pause or Resume
  every start. Paused is tafs cloud's `status` (the iPad's
  `cloud.paused`), never Home's `state`, which says `waiting` for a paused taf with a call held.
- **Times** are the account's, as the iPad's `AccountTime` (`Components.swift:196-247`): the
  next run as 14:05, a follow-up's end as "16 Nov 2026, 08:00", each with the zone's short name
  when the account's clock isn't this Mac's. A zone this Mac doesn't know is UTC, named as
  macOS names it, as the iPad's (`abbreviation(for:)`): newer systems say "GMT" for it, on the
  iPad too.
- **Results go to:** tafs' own places (Reply to the sender, Alert our phones, Email me), set at
  once (`PUT …/results`), at least one always on; then each place in a connected app, turned
  through the dial's next version, and **Add a place from a connected app…** (`setup.add_place`)
  for someone who manages the taf and may use Coach, which opens Coach on the taf
  (`TafSetupViews.swift:362-377`). A switch that is on and can't be turned off (the last of
  tafs' own places, or any for someone who doesn't manage the taf) stays green, as the iPad's
  tinted switch: macOS draws a disabled switch grey, so it is drawn as one
  (`LockedOnSwitchStyle`).
- **A change to the taf itself** (`PUT …/results`, pause and resume) answers the taf as tafs
  cloud runs it (`{taf}`: its `id`, `name`, `job` and `status` must be there), as the iPad's
  `CloudTaf`. An answer that doesn't read is no change, and says so. The taf it answers is the
  one drawn until Home's next read brings it. After a pause or resume the tafs are also read
  again, so the sidebar and the Overview say it: the iPad sets its own list's state instead.
- **A change** copies the live `setting`, changes one thing and sends it whole
  (`PUT …/knob`): tafs cloud makes the next version, and nothing runs from it until it goes
  live. Only whoever manages the taf, as KIFF says, gets the controls.
- **A change waiting to go live** (`KnobPendingPanel`): its version and KIFF's lines for it,
  then **Install this version**, as the iPad's Make it live: the versions and the dial are
  read again, and only if that version is still the one waiting is it installed as Versions
  installs it (above), its Card read first when it brings one. The iPad's label names Face ID
  ("Make 2 changes live with Face ID"); the Mac confirms with the security key or Touch ID, for
  which the shared words have no name yet, so it says Install this version. A Mac that can't
  install (view-only, or no security key) shows the line for an approval made on another
  device (`approval.device_can_not_approve_approve`).
- **The phone's:** approving an app event, which is signed with the approval key, then
  subscribed at planque on its routine route.
- **What went wrong** shows in red at the top of the screen, where the iPad says it in its
  error line: the dial that couldn't be read, a change that didn't go, a place or a pause
  tafs cloud refused (its words), or not every start paused (a 502 while pausing). Only the
  dial's own read error is cleared by the next read that works; any other stays, as the
  iPad's `lastErrorFrom`.

**Not sent** (`NotSentPanel`, the iPad's `notSent`, `TafSetupViews.swift:438-475`): under Results go to's places,
the taf's requests whose reply was given up on after its tries (`TafWork.unsent`: a delivery tafs cloud
marks `send_again`), each in tafs cloud's words, edged in amber, with **Send again** for whoever
manages the taf, through the same place and call as the work's own (`POST …/requests/{run}/deliveries/{place}/send`),
"Sending again…" while it goes. The work is read when the sheet opens. A failed read of the work, or a
Send again that failed, is said there in red. Nothing given up on, nothing drawn.

## Doors (`TafDoors`, `DoorsModel`, `TafDoorsViews`)

Ported from the iPad's `DoorsView.swift`, `DoorsModel.swift`, `TafsCloud+Doors.swift`,
`TafSetupViews.swift` (`DoorsList`), `TafPresentationViews.swift` (`TafKnocksPanel`) and
`NeedsYouView.swift` (its knocked rows). A door is where work reaches a taf from outside the
app (an email address, a WhatsApp number), with the answer going back the same way.
**Nothing here is signed:** tafs cloud takes each change with the person's session.

| Where | What |
|---|---|
| Setup › Starts when, for whoever manages the taf | Its doors (`GET /v1/tafs/{id}/doors`), each with its badge, label and tafs cloud's state words, and **Edit**, which opens the door's own screen; then **Add a door…**, disabled until the doors are read or while none can be added, as the iPad's. |
| A door's own screen | tafs cloud's settings line; its address (Copy address for email), Open as a switch (`PATCH …/doors/{door}` `{"open":…}`), and its day as a meter; who may give it work, each paired key ("You" only on this person's own), **Unpair** (`DELETE …/keys/{sender}`) and **Pair someone** (`POST …/keys`, `{"id", "name"?}`); **Remove door**, confirmed (`DELETE …/doors/{door}`); then the knocks waiting and the paired senders' messages; its footer. |
| Add a door | tafs cloud's apps not yet used, those that can tell who's writing first, searched by name (`POST …/doors` `{"app"}`). **WhatsApp's** opens tafs cloud's signup page (`/doors/whatsapp/connect?taf=…&state=…`) in the system's private sign-in sheet, which catches `tafs:` itself, so nothing is registered with macOS and no other page or app can hand a return in. Each signup sends its own one-use `state` (`WhatsAppSignup`: 32 random bytes), and only the return carrying it, for that taf, with a code, each field once, within 15 minutes, is taken; then the door is made with Meta's code and the number's ids (`{"app", "code", "phone_number_id", "waba_id"}`), as the session. A closed sheet says nothing; any other return says `door.whatsapp_signup_did_not_finish`, and nothing is sent. It shows only when tafs cloud offers WhatsApp. A Slack door is approved, so its row says to approve on a device that can. |
| Activity, for whoever manages the taf | First, the knocks waiting (Do it, Pair them, Ignore) and the paired senders' messages, read when tafs cloud offers doors (`doors_offered` on Home). |
| Needs you | A row per taf with knocks at its doors (Home's `doors[].knocks`), opening it on its Activity. |

- **A knock's answer** is `POST …/doors/knocks/{knock}` with `action` (`do` with the person's
  words, `pair` or `ignore`). Pair reads the doors again; Ignore and Do it take the knock away.
  Too many at once says the app's line (`door.knock.too_many`), not tafs cloud's.
- **A read that fails is tried twice more**, after 1 and 3 seconds; only then does it say so.
- **A Slack door with its channel's subscription isn't removed here:** the iPad stops planque's
  subscription first, signed; without planque it says to start from Connected apps first
  (`door.start_connected_tools_first_slack`), and so does this Mac.

### A door from another application (`APIDoorPanel`)

Ported from the iPad's `APIDoorViews.swift` and `TafsCloud+APIDoors.swift`: a door whose `kind` is `api`, a company's
own software handing the taf work with a key (tafs docs/doors.md). Drawn for what tafs cloud sends; its
`TAFS_API_DOORS` decides, never the app.
- **Its panel:** "From another application" and its name, Open; requests refused until it's open again
  (`door.api.paused`); today's count against its cap; its last request in tafs cloud's words only, never the raw
  status. Then its keys (at most two), each by its name, else its last four, with when it was made and last used, and
  **Revoke**; at most two keys; the boundary line; **Remove door**.
- **On this Mac's security key**, as a taf's removal is: tafs cloud's `doorSigned` takes `KIFF-Passkey-Assertion`
  through `checkSigned`. Each is the act's own request, approved once (`KeyAct`), named in the PIN sheet as the iPad's
  reasons:
  - **Open it again:** `PATCH /v1/tafs/{taf}/doors/{door}` with exactly `{"open":true}` ("Open {app}'s door again").
  - **Revoke a key:** `DELETE …/doors/{door}/keys/{key}` ("Revoke “{key}”"), asked first with what it means.
  - **Remove door:** `DELETE …/doors/{door}`, asked first with the API door's own body (its keys stop working).
- **Pausing is never signed:** `PATCH` with `{"open":false}` on the session, as every door's switch.
- **A closed sheet** sends nothing and says nothing; without a key on this Mac, each says to approve on another
  device.
- **API instructions**, a row under the boundary line, as the iPad's (`APIInstructionsView`): a sheet with where to
  send work (`APIInstructions.endpoint`), an example request that reads the key from the caller's own secret
  (`$TAFS_API_KEY`), single-quoted, that the key isn't here, and the boundary. **The endpoint is always rebuilt on
  tafs cloud's own address, over HTTPS**, keeping the door's path only when it's plain (`^/[A-Za-z0-9/_.~-]*$`), never
  a query or a fragment; anything else is tafs cloud's address alone. That's every app's shared rule
  (`vectors/api-door-endpoint.json`), hardening the iPad's host pin: the example is a shell line pasted with the
  developer's key, so it never names another host, and a path can't carry `$ ( ) ; & '` into the shell.
- **New key**, as the iPad's, on this Mac's security key (`KeyAct.newAPIDoorKey`: tafs cloud's
  `POST …/doors/{door}/keys` with `{"name":…}`, at most two live keys), named as typed or the door's own name
  (at most 60). The key comes back once and is shown in its own sheet (`IssuedKeySheet`) with Copy, where to send
  work and the example; leaving it forgets the key, and the list only ever has its last four. As the iPad covers
  the key from the app switcher and recording, **the sheet's window is kept out of screenshots and screen
  recording** (`CaptureShield`, `NSWindow.sharingType = .none`), and **a copied key leaves the clipboard after a
  minute** unless something else was copied since (`SecretClipboard`, as Android's).
- **A Slack door's removal** stops its planque subscription first (`PlanqueClient.Safe.deleteTrigger`, a safe
  route the device key signs), as the iPad's `removeSlackDoor`; if planque refuses, the door stays and says why.
- **Not here:** a drafted door's Approve, which issues a key too (`DoorDraftCard`, the phone's for now).

## Tests

`scripts/test.sh taf`: the Cards as tafs cloud sends them, a Card that doesn't read, a Card
with no rules, the figure from money and from calls, no figure when used is unknown or the
units differ, a used over the limit, money in its language, and each state's chip. On a Mac: a taf's chat reads
that taf's conversation without asking which taf is Coach, a Card with no rules has no panel
under it, and the screenshots `build/screenshots/taf-<tab>-<language>.png`, each tab in three languages.
`scripts/test.sh contracts` reads both contracts; the Mac tests read the Activity and Setup
from them, check every request is a `GET` of that taf, a filter asked for again, and a refused
Setup.

The page's parity with the iPad (`TafPageTests`, `TafPageScreenTests`): tafs cloud's time zone
words, a taf's job, the Card's issuer, how a Card counts each tool, the Setup's versions counts,
an `ask_coach` card read from the thread, a taf's credits and its next page, its notes and
Forget. On a Mac, in light and dark (`build/screenshots/taf-<part>-<light|dark>.png`): the Card
tab for a manager and a member (and in French), a Card's face with its issuer, How this is
counted, the Setup with its ring, a chat's `ask_coach` card with and without Ask Coach, Share,
the Activity with its Cards in the side column and none beside its calls, Usage and See all;
Starts when with its doors and Change when it starts with Coach, Results go to with Add a
place and a locked-on switch drawn green, −/+ filling their thirds; only reads go from the Card and Setup tabs, Coach asked about a card has its words in the box
only for whoever manages the taf, the ring's places, More runs, and Forget put back or gone.
