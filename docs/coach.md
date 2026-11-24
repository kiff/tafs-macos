# Coach

Coach is where a taf is set up, an app is connected and a taf is changed, in conversation.
**Today this screen reads Coach's chat, writes to Coach, and answers its choices. Approving a connection or a Card stays the phone's: each card is drawn up to the approval, with Decline, and says where to approve.**

## What is read (`Coach`, `Thread`, `CloudClient`)

| Call | Route | What |
|---|---|---|
| `coach()` | `GET /v1/setup` | The account's Coach, or none before Coach is started. A plain read: unlike the phones' first read it sends no time zone, so it changes nothing on the account. |
| `thread(of:session:)` | `GET /v1/tafs/{id}/conversation[/{session}]` | The chat as one ordered list (`items`): messages, cards and held calls by time; with a session, that chat's alone. |
| `chats(of:)` | `GET /v1/tafs/{id}/chats` | Coach's chats (`session`, `started`, `updated`, `title`), each one strictly. |
| `coachAndTools()` | `GET /v1/setup` | The same read as `coach()`, its answer's `tools` read too: Coach's tools still to give (`CoachTools`, below). Nothing more is sent. |
| `ConnectionsSource.grants()` | planque, `GET /v1/accounts/{tenant}/grants` | The account's grants, with this device's proof (`Planque-Device-Signature`, no prompt), as Connect apps reads them: what an approval's connection line, a hand-over's tool titles and "Taking shape" read. Only Coach's own chat in the signed-in window reads it, once its cards name a grant or a hand-over lists tools, and again as they change. |
| `AccountClient.draft(id:)` | KIFF, `GET /v1/me/agent-drafts/{id}` | The Card KIFF drafted for an approval (`component.draft`), as the iPad's `KIFFClient.draft(id:)`: with the session, unsigned. Read once each card names it, again as its answer changes, and on Try again. |

planque's grants and KIFF's drafts are kept in memory only, and dropped at sign-out: they name the
connected apps' accounts and the taf's Card terms. Nothing of them is written to disk, logged or sent on.

The app draws the list as it comes. It places and folds nothing itself.

| Item | Drawn as |
|---|---|
| A message from the person | Their words on the brand's gradient, at the right. A time, centred, on the first item and after an hour's gap |
| A message from Coach | "Worked for 32 s", which opens the run's steps folded as the iPad's (`WorkRows`); then its words, with no bubble |
| A job's instruction (`kickoff`) | A small note |
| The plan (`steps`) | tafs cloud's `line` and the step in hand with its mark; opened, every step with its mark, the one in hand semibold, a skipped one struck through |
| A choice (`confirm`) | What it asks, then a white pill for each answer. Answered: one folded line, "{question} · {chosen}" |
| Questions (`questions`) | The iPad's `QuestionsCard`: Coach's words, its title as an eyebrow with "{n} of {total} answered", each question numbered with its options and **Something else…**, then **Send answers** and **Chat about this**. Answered: one folded line, "Your answers · {tafs cloud's words}" |
| An approval that waits | As the iPad's `SetupApproval` (`SetupChatView.swift:1620-1802`), up to the approval: edged in amber, "Needs you · approve", what it asks, the connection's line from planque's grant ("Stripe is connected", "Signed in at Stripe · reading what it offers") or tafs cloud's, the Card KIFF drafted for it (its title and KIFF's lines; under tafs cloud's `signs.words`, dimmed, when the Card is approved next; "Reading KIFF's words for this connection…" until read, or why not with **Try again**), or, once planque's grant for it is read, tafs cloud's words for a Card approved next, tafs cloud's wider line when it sends one, **Decline**, and where to approve |
| An approval that didn't go through | Edged in red, "Didn't go through", tafs cloud's line for a refused request whole, else planque's why, else "It didn't go through. Nothing was connected."; "Coach mode has to change this request before you can approve it." when planque failed its grant, else **Decline** (even once answered) and where to approve. One approved that planque then failed or disconnected is this card, with planque's why, as the iPad's `approvalFinished` |
| An approval a newer one replaced | As the iPad's `replaced` (`SetupComponent.swift:450-456`): another approval for the same grant, shown later, makes it history. One line with a grey ↓: "Approved · Setup asked for more below", "Declined · Setup asked again below" or "Setup changed this request: see below", even while it waits. A ⌄ opens it: "Earlier request" with **Fold**, its words and "A newer request for this connection is below.", and nothing to answer |
| A sign-in that waits | Edged in amber: "Needs you · sign in", "Sign in at {app}", its note, tafs cloud's wider line when it sends one, where to sign in, and **Not now** |
| An approval already answered | One folded line, as the iPad's `outcome` (`SetupChatView.swift:1597-1618`): ticked in green, "Approved · {the Card it signed}" with KIFF's lines under it, else "Approved · {title}", "Already approved · …", or by the vendor; a decline ("Declined · {title}") with a grey minus. Read from tafs cloud's settled `answer`, else its exact English: nothing reads as approved by default, nor while planque's grant for it is failed or disconnected (then it didn't go through). A ⌄ at its end: a click opens the card again, edged in green (amber once declined), "Approved" or "Declined" with **Fold**, then the card as above. Nothing on it answers again |
| A note (`notice`) | A panel in its tone's colour, its title in that colour |
| The hand-over (`result`) | Edged in green: "Set up · the taf's name", what it does, its tools by the title their approval asked for them by ("Refund a payment", the iPad's `toolTitle`), else in words ("list emails", never `list_emails`), and **See it on {taf}** once the taf is listed ("Setting up {name}…" until then). Failed: "{name} wasn't set up: {why}." and no button. Needing a plan: **Choose a plan**, to Plan & usage |
| A new version (`result` whose taf `improves` one) | As the iPad's `improvement` (`SetupChatView.swift:1380-1420`): edged in green, "New version · the taf's name", what it does, tafs cloud's note of what changed ("Can now list your Google Calendar events."), and no tools. Made: **See version {n}**, which opens that taf's Versions; "Version {n} is made." when the taf isn't listed. Being made: the same button, greyed, "Preparing the new version…" with a spinner. Not made: "{taf}'s new version wasn't made: {why}." and "Coach knows, and hands it over again." Nothing goes live from it |
| A call KIFF held | "Needs you · approve". It is answered in Needs you. |
| A drive's card (`drive`) | Nothing: Coach driving the phone's own screen is the phone's (docs/drive.md), never a question to this Mac |
| Anything else (a drive's end, a kind this app doesn't know) | Nothing |

- **A run's steps** are tafs cloud's words for them, never a tool's name: a tick, a red mark
  for a failure, an arrow for one not made ("not made · read first"), and "{n} tries".
- **Coach's words are drawn as the iPad's `MarkdownText`**: no Markdown mark shows, a link is
  its label only, and every piece is `Text(verbatim:)`. A ``` fenced block is its lines as
  written, no mark read inside, in 14 mono on the raised ground (padding 10, radius 8); one
  never closed is code to the end, as while an answer streams. The plan stays where it was shown.
- **A connection made while Coach is shown** shows its receipt, with board 5 (docs/connections.md ›
  The receipt). While a connection card waits, Coach's chat is read again every 4 seconds, at
  most 75 times, while Coach is on screen.
- **Approve stays the phone's.** Approving a connection or a Card grants at planque (the phone's
  approval key, then planque's approve) or confirms KIFF's Card (`POST /v1/me/agent-drafts/{id}/confirm`),
  or signs both as one pair: none is an act this Mac's security key approves (`KeyAct`, docs/approvals.md),
  and nothing is ever signed at planque from here. The card says where to approve. **Decline** and **Not
  now** answer it with `declined` or `not now`, and grant nothing, as the iPad's (outside its `ApprovalGate`).
  planque's own words for the request, its terms and the profile words the phone's Approve matches aren't
  drawn here: they go with Approve.
- **A sign-in wider than the job is said on the card** (`WiderLine`, as the iPad's): when the
  app's sign-in can't be narrowed to what the taf uses, tafs cloud marks a waiting approval or
  sign-in card `wider: {words}`, in the reader's language. Its words are drawn as sent, 14
  medium in amber text, above the card's buttons: on an approval after what it asks and the
  connection's line, before **Decline**; on a sign-in after its note, before where to sign in
  and **Not now**. With no words, nothing is drawn.
- **Coach's thread is read with this device's planque proof** (`Planque-Device-Signature`), as
  the iPad's `loadSetupThread`: tafs cloud marks the cards (`wider`, and `signs`) only on a read
  that carries it (kiff/tafs `markSigns`). It's `PlanqueClient.grantsReadProof`, the proof a
  taf's Setup read sends, signed with the device key and no prompt: it reads, it grants
  nothing. No `?can=`: this Mac signs no step past connect and cards. Without a device key the
  thread is read without it, and the cards come unmarked. A taf's own chat never sends it, as
  on the iPad.
- **A decline** is known only by tafs cloud's words for the answer, which it writes in the
  app's language: "Declined". An approval or sign-in answered another way (`wrote`,
  `no_answer`) draws nothing.
- **See it on** opens the taf's own page, or the Overview when the list doesn't have it, and
  closes Coach, as the iPad's `requestedTaf` with `coachOpen = false`. **Choose a plan** closes it
  too, for Plan & usage.
- **See version {n}** opens the Versions of the taf the new version is for, as a sheet over Coach,
  as the iPad pushes its `VersionsScreen`: the taf tafs cloud knows by `improves`, else the one
  whose agent it names, else the result's own taf's (`Thread.Card.improvedTaf`, the iPad's
  `improvedTaf`, `AppModel.swift:9807-9811`).
- A card is known by its `key`, which is unique in the thread, never only by the name the
  model gave it: the model may reuse a name.
- An item that doesn't read is left out. An answer with no ordered list is unreadable, never
  an empty chat.
- **With no Coach, or an empty chat**, the screen is Coach mode's start, as the iPad's
  `introBefore`: "Coach mode" in 30 rounded bold in Coach's colour, then a 16 soft lead,
  centred in the height. The lead is the Mac's own shared line ("Set up a new taf, connect an
  app, or change how one works."): the iPad's says the person approves with Face ID, which
  this Mac can't do yet. A chat with a run going on and nothing in it yet is not the start.
- **The message box** is the iPad's: the field 16 with padding 14/10, Send a 40 circle with a
  16 bold arrow, on a 20-radius panel. **While Coach works** (a message on its way, an answer
  being written, or tafs cloud's `working`), the box asks for "Write the next message".
  Not on the Mac yet: the iPad's Stop in Send's place, which needs tafs cloud's route to stop
  a run, and its mic, which needs dictation.
- **The person's words** are on the brand's gradient, radius 18, keeping 48 free on the
  left, sent or still going.

## What a conversation carries (`Thread`, `LiveAnswer`, `Rich`)

A card item is `{key, session, answer?, component: {…}}`, as tafs cloud's `ThreadComponent`
sends it: what the agent showed (`id`, `type`, `title`, `text`, `options`, `waits`, …) is
read from `component`, and the card's key, its chat and tafs cloud's answer from beside it.

| Read | From | What |
|---|---|---|
| A run's work | a message's `work`: `ms`, `steps[]` | How long it worked, in the shared words by the iPad's rule ("32 s" under a minute, else "1 min 59 s"), and each step by tafs cloud's `words`, failed or not, with its one line of `why`. A step with no words is left out; a tool's name is never kept. A step refused back unmade (`not_made`) isn't a failure. |
| A plan | a `steps` component's `steps[]` (`label`, `status`) and `line` | Each step and where it stands, and tafs cloud's line for it ("Step 2 of 3: …"). |
| A notice | a component's `tone` | `info`, `success`, `warning` or `error`. |
| A hand-over | a `result` component's `taf` (`name`, `agent`) and `tools`; the card's `answer.outcome` | The taf it is about, by its agent, and its tools in KIFF's words; once tafs cloud answered it, what came of it: the taf made (`taf_id`), a `version`, why it `failed`, or `plan_needed`. A component's own `taf_id` is a dial card's, never the hand-over's. |
| A new version | a `result` component's `taf.improves` and `taf.note`; the card's `answer.outcome` (`version`, `failed`) | As the iPad's `SetupComponent.Taf`: `improves`, the tafs cloud id of the taf this is the next version of, makes the result a new version, never a new taf; `note` is what changed, in the owner's language (blank is none). What came of it is `Thread.Card.improvement`, as the iPad's `SetupThread.improvement`: `failed` first, then the `version` made, else being made. |
| How an answered card folds | the card's `type` and `answer` (`Thread.Card.fold`) | As the iPad's: an approval approved or declined folds to a line that opens again; a choice, a sign-in and questions to a line; a plan, a note, a hand-over and a taf's ask stay whole, as does any card with no answer the person chose (`wrote`, `no_answer`). |
| An answer | the card's `answer.state` and `words` | Shown as answered only when the person chose (`answered`). One they wrote past (`wrote`) or that stopped waiting (`no_answer`) waits no more, and shows no answer. |
| A connection already made | an approval component's `connection`, when `done` | tafs cloud's line for it. |
| A sign-in wider than the job | an approval's or a sign-in's `wider.words` | tafs cloud's words, as sent (`Thread.Card.widerWords`), read leniently as the iPad's `SetupComponent.Wider`: missing, `null`, blank words, words that aren't text, or a `wider` that isn't an object are no line, and the card reads as before. |
| The live steps | the stream's `activity {step, call_id}` and `step {call_id, status}` | Listed as they come, without the trailing "…", and each ended **by its call**: calls may overlap, and a step with no words ends without touching a listed one. `done`, `error` (failed) or `not_made` (its own state, not done). At most 200. |

- **A run's steps are folded as the iPad's `WorkLog.rows`** (`WorkRows`): tries of the same
  step after a failed or unmade one are one row, with the last try's outcome and how many
  tries; a failed step is left out once something worked, or while the answer still runs;
  when nothing worked, the failures stay; a step not made and not tried again stays. The live
  steps fold the same way, and the step at work is the live line, never a row.
- **A time shows** on the first item, and on one an hour or more after the one before it, as
  the iPad's `gapTime` (`Thread.Page.showsTime`). A card's time is the card's `at`.
- **Coach's words are read as the iPad's `MarkdownText` reads them**, so no mark shows as
  written (`Rich`): bold, italic, inline code, headings, bulleted and numbered items. **A link
  is drawn as its label only, and an image as its words: nothing leads anywhere.** HTML and a
  mark with no partner stay as written. Text over 20,000 characters is left plain.
- **Declining** (`CloudClient.decline`) sends `declined` to an approval and `not now` to a
  sign-in, and refuses any other card before anything is sent. Saying no grants nothing, so
  it is never signed. Those two words are the only answers this app ever sends such a card.

## Coach's conversations (`CoachModel.chat`, `fresh`, `ChatTarget`)

As the iPad's `setupChat`, `setupFresh` and `setupTarget` (`AppModel.swift:6716-6720`,
`7000-7014`, `7164-7188`, `7285-7303`):

- **Coach opens on its newest chat** (`updated`), read by its session. Without the list, or with
  none yet, the thread reads as before.
- **New conversation** (the pencil by Coach's title, `coach.new_conversation`) empties the
  chat and reads nothing until its first message; an empty chat is already one, so it does
  nothing there. What's typed stays in the box. It cancels the answer streaming in the
  conversation before, as the iPad's `newSetupChat`, and that answer touches nothing of the
  new one after any wait: its end, a read of its thread, or its words.
- **A Mac difference:** a message refused for want of the AI-data consent stays here as the
  sent message (the iPad puts it back in the box), so New conversation also drops its consent
  ask. Card states are left as they are, as on the iPad.
- **Where a message goes:** a new chat (`new_chat: true`), else the chat shown (`session`),
  else the live one. Coach's say `new_chat_after_handover: true`: tafs cloud starts a new chat
  for a message to one that already handed a taf over.
- **The first message's answer** (or the stream's `session` event) names the new chat, which
  is then the one shown. When it says `new_session: true` with another chat, Coach goes on in
  that one; the old one stays tafs cloud's. What comes back for an earlier conversation is
  dropped.
- A taf's own chat has no conversations: its messages go to its live chat.

## Coach's title row, Previous conversations, and Start a new taf

As the iPad's Coach mode (`CoachMode.swift:13-31`), its toolbar (`SetupChatView.swift:105-110,
136-141`), `SetupChatsList` (`:803-857`), `openCoach` (`AppModel.swift:6767-6778`),
`startNewTaf` (`:6801-6804`), `openSetupChat` (`:7124-7135`), `loadSetupChats` (`:7138-7143`)
and `loadSetupThread` (`:7328-7375`):

- **Coach's title row:** Back on the left, which closes Coach (Esc too), back to the screen
  under it; then ⤢, which makes Coach fill the window and brings it back to its width ("Full
  screen", "Back to its width"); on the right, New conversation (the pencil, which does nothing
  on an empty chat) and the conversations' menu, with Previous conversations.
- **The sidebar's Coach** only opens Coach, as `openCoach`. Coach closes from its own Back.
- **Previous conversations** lists Coach's chats (`GET /v1/tafs/{id}/chats`) as tafs cloud
  lists them: each by its title and when it was last written to, the one shown marked. One
  click reopens it: what was on its way belonged to the chat before (a consent ask with it),
  and the chat is read by its session. A list read that fails keeps the list as it was. A
  reopen whose read fails keeps the page shown, with "The conversation couldn't be loaded: …" and
  Try again under it, as `loadSetupThread`'s `setupError`. Done (Esc) closes it.
- **Archive** (`coach.chats.archive`), as `SetupChatsList`'s swipe (`SetupChatView.swift:800-873`)
  and `archiveSetupChat` (`AppModel.swift:7533-7551`): asked first ("Archive this
  conversation?", with what it means), then `POST /v1/tafs/{id}/chats/{session}/archive`. tafs
  cloud keeps it out of the list and the thread from then on, on every device; it isn't
  deleted. The chat shown gives way to a new conversation. One tafs cloud refuses says
  "Not archived. {why}" at the top of the list, which stays as it was.
- **Archived**, at the end of the list, as `ArchivedSetupChats` (`:875-925`): the archived
  chats (`GET /v1/tafs/{id}/chats/archived`), each opened with a click, and **Put back**
  (`POST …/chats/{session}/unarchive`), which reads the list again. A read that fails keeps
  what was read; "Not put back. {why}" when tafs cloud refuses. ‹ Back returns to the list.
- **After sign-out**, an archive, a put-back or an archived list that comes back late does and
  says nothing.
- **From your watch** (W11), as the iPad's `WatchDaysSection` (`WatchDaysViews.swift`,
  `TafsCloud+WatchDays.swift`, `WatchDays.swift`): after the chats, the days the person asked
  from their watch, newest first (`GET /v1/watch/days`), each with how many requests, under
  "From your watch". Only the person's own, read only. A day that doesn't read is left out; a
  read that fails, or tafs cloud's switch off (404), draws no section. A day's title is
  "Today" for tafs cloud's `today` (else this Mac's day), else its weekday, day and month in
  the person's language. **A day opens in place** with ‹ Back, as Archived does (the iPad
  pushes it), oldest first (`GET /v1/watch/days/{date}`): each turn's "⌚ Sent from your watch"
  and when, the person's words, then the taf that took it and tafs cloud's line, else its
  words for the state; a reply sits under what it answers. A message to a taf (`kind: "taf"`)
  is that taf's chat, not Coach's, and isn't listed. An answer for a day asked before the last
  is never drawn, and nothing of a day is kept once it's left. **Mac difference:** a turn's
  time is in this Mac's zone; the iPad writes it in the account's.
- **After sign-out**, a chats list or a reopened chat that comes back late is dropped, as the
  iPad's `accountGeneration` guard.
- **Start a new taf**, from Home's Own words, the gallery's own words, and the sidebar's +
  when tafs cloud sends no gallery (`HomeSplitView.swift:434-438`; with one, + opens it, see
  `docs/overview.md`), opens a new conversation in Coach, so Coach mode's start shows, whether
  Coach was open or not. Asked before Coach is read, Coach opens on a new conversation once it is.

## Coach mode: the panel over the screen (`CoachPanelHost`, `CoachPanelModel`, `CoachPanelWidth`)

As the iPad's `CoachPanel` and `CoachView` (`CoachMode.swift:8-111`):

- **Coach slides in from the right over the screen**, which stays in view: the Overview, a
  taf's page with its tab, any screen. It sits on the background with a shadow to its left; the
  sidebar is never under it unless it fills the window.
- **Every way in opens it, on the right chat:** the sidebar's Coach (the chat it had), Start a
  new taf (a new conversation), Needs you's Open Coach (that chat), Improve in Coach and Change
  the workflow (a new conversation on the taf, over its page), an `ask_coach` card's Ask Coach
  (the same, with the card's words in the box, nothing sent), a job handed from the Overview
  and the brief's next move (their words in the box). Connect apps' Not listed? opens it too.
  A connection made while it's open shows its receipt over it, as before.
- **Its left edge drags it** wider or narrower: never narrower than 380 points, and never so
  wide that less than 240 points of the screen stays in view (`CoachPanelWidth`). It opens at
  440. The width chosen, and whether it fills the window, are kept on this Mac (`coach.width`,
  `coach.full`, as the iPad's `@AppStorage`), for the next time.
- **⤢ fills the window,** the sidebar too, and brings it back to the width it had.
- **Back** (Esc) closes it, back to the screen under it as it was, a taf's page and its tab
  too. Closing never ends a conversation.
- **The sidebar's Coach** is the chosen one while Coach is open. Needs you leaves out the chat
  Coach shows while it's open (`NeedsYouCount.shown`).
- With Reduce Motion on, it fades in and out rather than slide, as the iPad's.

### Mac differences

- **The screen beside Coach stays usable:** nothing dims it, and a click on it doesn't close
  Coach, where the iPad dims its screen and a tap outside closes Coach. Back and Esc close it.
- **The edge doesn't close it:** dragged past its narrowest, it stays at its narrowest (the
  iPad's closes). It keeps points, not the iPad's share of the screen, since a Mac's window is
  any size.
- **See version opens Versions as a sheet,** where the iPad pushes it inside Coach.
- **No swipe:** Archive and Put back are each row's own button at its end, and its right-click
  menu; and no swipe of the conversation closes Coach.

## Starting Coach (`CoachStart`, `PasskeySession`, `CoachModel.startSetup`, `followStart`)

As the iPad's `startSetup` (`AppModel.swift:7556-7635`), `TafsCloud.startSetup` and
`CoachStart.startable` (`TafsCloud.swift:2247-2290`, `2470-2478`), `KIFFClient.submitNoToolsDraft`
(`KIFFClient.swift:1261-1269`) and `SetupChatView.introBefore`'s Start (`SetupChatView.swift:196-233`),
on Windows' passkey route (tafs-windows `CoachStart.StartAsync`), for an account with no Coach yet:

- **Who may start it** (`CoachStart.mayStart`): a Mac on its security key's route
  (`ApprovalRoute.passkey`), with the key that goes with it (`PasskeySession`). Setup's draft
  grants authority, so it is approved by the security key, through the PIN sheet
  ([approvals.md](approvals.md), "Passkeys on macOS 12"), and sent as `KIFF-Passkey-Assertion`.
- **It fails closed.** Without the security key's session, `start` asks nothing, reads nothing,
  enrols nothing, mints nothing and sends nothing: it says "This device can't approve…". The
  device key never approves the draft in its place, and a draft is sent only as
  `PasskeySession.Signed`, which only `signDraft` makes.
- **Off for now:** the route is given only once `Features.macPasskeyApprovals` is on, so every
  Mac today says, where Start would be, "This device can't approve. Approve on another device
  signed in to your account." (`approval.device_can_not_approve_approve`), and **follows the start
  made on the phone**: Setup is read again every 10 seconds while it shows, and once the phone
  has started Coach its thread shows here. Only reads.
- **On a Mac that may**, Start, in Windows' order:
  1. no device key: "Sign in with KIFF again: this sign-in can't sign for the Mac."
     (`sign_in.again_to_sign_device`);
  2. planque set up and Coach there: nothing more;
  3. no security key's session: it stops (above), before anything is asked;
  4. Setup read (`GET /v1/setup`), before anything is asked: Coach there and planque set up,
     nothing more; tafs cloud's first start, signed once with Coach's tools, isn't here yet
     (below), and nothing is sent;
  5. **the one approval:** the PIN sheet, then the key's touch, over Setup's draft
     (`{"agent_id":"setup","label":"Setup","no_tools":true}`), exactly the bytes sent, at a
     `signed_at` never used twice. Closed, nothing is enrolled or sent, and nothing is said. With
     Coach already there and only planque to set up, the owner confirms instead (Touch ID or the
     Mac's password, as Windows' gate). That prompt closed says "Cancelled. Nothing changed."
     (`approval.cancelled`, `OwnerPrompt`), and one that failed "Not sent: it wasn't
     confirmed."; either way nothing is enrolled, and a session that ended meanwhile says
     nothing. Refuse and Your step, whose call still waits, keep "the request is kept";
  6. planque's enrolment, if this Mac isn't set up (`PlanqueEnrolment`, see
     [connections.md](connections.md)), signed by the device key with no prompt, as the iPad's
     `signConfirmed`. planque's signer is armed only inside it, after the approval and its account
     check, and cleared when it ends. What stops it says why;
  7. the draft sent with its approval, then tafs cloud claims its key (`POST /v1/setup`,
     `{draft_id, claim_secret}`, unsigned with the session's token);
  8. then Coach's thread is read.
  A draft without its secret says "KIFF didn't answer as expected"; anything else says
  "Couldn't start." with tafs cloud's words, else KIFF's plain line, never a code.
- **The account is checked after every step**: the read, the approval, the enrolment (and inside
  it), the draft, and the claim (one more than the iPad's `:7615`). A session that ends drops
  what comes back and says nothing. Any change of session (a sign-out, a pairing, a new sign-in)
  rebuilds the window, and its going ends what the old one started (`coach.signedOut()`, the taf
  chat's, and a PIN sheet left open), as the iPad's `accountGeneration` (`AppModel.swift:887`, `:1472`).
- **Not here yet:** tafs cloud's first start, the tools batch and Coach's Cards signed once
  (`startCoachTogether`, `RequestsTogether` on the key); giving Coach's tools (the step is drawn, below);
  keeping planque's
  enrolment across launches (it lasts this session; asked again, planque answers `kept`, and
  nothing is minted). The iPad's "Starting asks for {biometry} once." isn't shown on this route:
  the shared words have no line for the security key there, and the PIN sheet says what it asks.

## Improving a taf (`CoachModel.improve`, `ask(about:words:mayUseCoach:manages:)`)

As the iPad's `improveTaf`, `askCoachAbout` and `deliverSetup`'s improvement
(`AppModel.swift:6778-6792`, `7536-7553`) and `SetupChatView`'s `starts` (`:552-636`):

- **Improving a taf is a new conversation on it**: nothing read, the taf kept as the one
  it improves. `ask(about:…)` also puts words in the box, nothing sent, and only for someone
  who may use Coach and manages the taf: the iPad's guard, in the model. Asked before Coach is
  read, the improvement and its words wait, and start once Coach is read.
- **Its first message goes to `POST /v1/tafs/{taf}/improve`**, which puts the taf's job, Card
  and latest calls in front of it. Its answer names the chat, which the conversation goes on
  in as any other; the taf is no longer the one improved. tafs cloud answers no message id
  there, so the sent message is found in the thread by its words, written about when it was
  sent, as the iPad's `SentMessages.merge`; any sent message goes after two minutes in any
  case. The Mac then follows the thread, as after any send (the iPad reads it once).
- **Its start:** what the conversation is about as a choice, New taf or "Improve {taf}"
  (`coach.what_conversation_about`); "Improve {taf}" (26 bold); `coach.improve_line`; and
  three examples (`coach.improve.*`) that send as they are. The choice and the examples wait
  while a message is on its way (`setupSending`).
- New conversation on an improvement with nothing sent starts a plain one.

## Reporting an answer (`AnswerReport`, `ReportAnswerSheet`)

As the iPad's `reportable`, `ReportAnswerSheet`, `canReport` and `reportAnswer`
(`ReportAnswerSheet.swift:1-137`, `AppModel.swift:5429-5465`, `TafsCloud.swift:1483-1512`):

- **Report this answer**, with the flag mark, is in the context menu of an answer Coach or a taf wrote: never the
  person's own, a run's kickoff, an empty one, or one tafs cloud has no id for yet.
- Its sheet: what's wrong with it (Offensive, Harmful, Wrong, Other), a note of at most 1,000
  characters (optional), and that a person at KIFF reads the report with the answer as it
  was written. Send needs a reason.
- `POST /v1/tafs/{id}/messages/{message}/report` with the reason, the note when there is one,
  and the chat it's in (`session`, as the thread names each message).
- Sent, it thanks the person, or says they had reported it already. Not sent, it stays open
  with why: tafs cloud's words when it sent some, "This answer isn't on tafs cloud any more"
  for a 404, else the app's own line. An answer that comes after the person signed out says
  "You signed out." (`common.you_signed_out`), as the iPad's account guard.

## Writing to Coach (`CloudClient.send`, `CoachModel`)

`POST /v1/tafs/{id}/messages` with the person's words. It starts a run, so it is only ever
sent for what the person typed and sent with Return or Send.

- **A message is 1 to 2,000 characters once trimmed.** Anything else is not sent.
- **The sent message stays in view**, faded, until the thread has it. tafs cloud answers the
  send with the message's id, and the thread's copy carries the same id.
- **Then the thread is read again every 4 seconds, at most 30 times**, while an answer is
  owed, as the phones do when the answer can't be streamed.
- **A message that didn't go stays where it was**, with tafs cloud's own words for why when
  it sent some ("Halted: nothing runs until it's resumed."), and Retry, which sends the same
  words.
- **Retry never sends the same message twice.** tafs cloud's route takes no key that would
  let it recognise a repeat. So before sending again, Retry reads the thread once: if the
  person's latest message there is the same words, sent since the first try, the first try
  did arrive (only its answer was lost) and nothing more is sent.
- One message goes at a time: the box sends again once the last one is in the thread or failed.

### The answer as it is written (`StreamEvent`, `LiveAnswer`, `NetworkLineStream`)

The message is sent on the stream route (`POST /v1/tafs/{id}/messages/stream`), so the answer
shows as Coach writes it. tafs cloud trims the stream to what an app shows.

| Event | What the app does |
|---|---|
| `session` | Notes the person's message's id, to match it in the thread, and the chat it went to (a new one, or one tafs cloud started after a hand-over). |
| `text` | Adds to the answer, drawn under the person's message as the iPad's `SteadyMarkdown` (below). |
| `state`, `activity` | The one line of where the run is, in tafs cloud's words; "Thinking…" before either. |
| `step` | If it failed, tafs cloud's one line of why, under the answer. |
| `held`, `taken`, `component`, `part` | The thread now has something the stream doesn't carry: it is read again. |
| `end` | The answer is over: the thread is read, which has it whole. If the run stopped with a reason, tafs cloud's words for it are shown. |
| `thinking` | Nothing. The model's thinking is never drawn. |

- **The answer streaming in is drawn as the iPad's `SteadyMarkdown`** (`SteadyText`, in Coach's
  chat and a taf's):
  - **No mark shows on the way:** what it's in the middle of is closed first (`Rich.healed`, the
    iPad's `MarkdownBlock.healed`, kiff/tafs#285). Bold or inline code left open is closed, a
    link whose address isn't in yet shows its text, and a mark just opened with nothing after it
    waits for its words.
  - **It comes at an even pace,** not in the bursts it arrives in. Every 16 ms at least two
    more characters show, else a sixth of what's left (`Rich.paced`). The first words show at
    once, and each new piece goes on from where the last stopped.
  - **With Reduce Motion,** all of it shows at once.
- An event that isn't what the page says (not JSON, a number where words should be, a name
  this app doesn't know) is dropped. It is never drawn.
- **A message is never sent twice.** If the stream can't open, the app reads the thread
  first: if tafs cloud has the message, it only follows the thread; only if it doesn't is the
  message sent on the plain route. **Once the stream route has answered, tafs cloud has the
  message**: a stream that then drops, even before its first event, is never sent again, and
  the message is not left looking unsent.
- A refusal on the stream is handled as on the plain route: the consent is asked for, or the
  message stays with tafs cloud's reason.
- The stream goes to tafs cloud's streaming address, the one the phones use, over HTTPS only.

### Answering a card (`Thread.Card`, `CloudClient.answer`)

A card Coach shows may wait for the person: its run pauses on it. The answer goes back as
data (`POST /v1/tafs/{id}/components/{component}/answer`), never as text in the chat.

| Card | On the Mac |
|---|---|
| A choice (`confirm`, with options) | Its title and text as Coach wrote them, and a button for each option. One tap answers it. |
| The loop card (`confirm`, id `tafs-loop-N`, with `loop`) | In a taf's own chat, when a run read page after page of one list: tafs cloud's words, "Still reading", the read, and **Read on** / **Stop here** (values `tafs_loop_continue`, `tafs_loop_summarise`), as the iPad's `LoopCardView` (tafs#1861) and Android's `answerTafCard`. It's a choice that waits on the owner, so it's drawn and answered as one: the value, with the card's own chat, to the taf's route, then the run that goes on is followed. |
| Questions (`questions`, with questions) | In Coach's own chat, for someone who may use Coach, while it has no answer: each question's options, or the person's own words, then **Send answers**, once every question has an answer. |
| An approval or a sign-in (`approval`, `sign_in`) | "Needs you · approve". **Never answered here**: its answer is a signature, which arrives with approvals on the Mac. |
| A card already answered | What was answered, in tafs cloud's words. |

- **Only a card's own options can be sent.** An option that isn't the card's, and any answer
  to an approval or a sign-in, is refused before the network, whatever options the card carries.
- An option with no label or no value is left out: it can't be read, or can't be answered.
- While the answer is on its way the card says so; then the thread is followed, and the
  card shows what the thread says was answered. The app keeps no answer of its own.
- A card that no longer waits (409) is read again as it is. Any other refusal stays on the
  card with tafs cloud's reason, and the card still waits.

### Questions (`Thread.Card.Question`, `QuestionSelection`, `QuestionsCard`)

As the iPad's `QuestionsCard`, `QuestionSelection`, `answer(_:_:)`, `cardRef` and `answerCard`
(`Views/QuestionsCard.swift`, `Model/QuestionAnswers.swift:62-99`, `AppModel.swift:6708-6711`,
`8355-8385`, `KIFF/TafsCloud.swift:1355-1389`):

- **Every word is Coach's:** each question's text, its options with their descriptions, and its
  note. The app adds **Something else…**, for the person's own words, and **Chat about this**,
  which puts the card away ("You're talking these questions through with Coach.", with Show
  them again) so the person writes instead.
- **One answer for each question:** a choice, several on a multi question (in Coach's order),
  or the person's own words, never both. Opening Something else… clears the picks; picking a
  choice closes the field; blank words are no answer. Send answers waits until every question
  has one.
- **Who and where:** only in Coach's own chat (the iPad's `setupTaf`), for someone who may use
  Coach (`mayUseCoach`). A taf's own chat, or someone without it, shows what the card asks.
- **Whenever it has no answer**, whatever `waits` says, as the iPad's `QuestionsCard`.
- **Sent as data** (`{"answer": {"<question>": {"value"} | {"values"} | {"own"}}, "session"}`),
  as the iPad's `CardAnswerValue.questions`, to the card its id names now (`cardRef`: the one
  waiting under that id, else the latest), in that card's chat. It grants nothing, so it isn't
  signed. Only the card's own questions, each answered, are ever sent.
- **tafs cloud's answer is `CardAnswered`** (`session`, `run`, `status`, all text). Its chat is
  the one shown from then on, for a new conversation (`settleSetupChat`). Then **the answered
  run is followed as it's written**, as the iPad's `followAnswered`: `GET /v1/tafs/{id}/runs/{run}/stream?after=0`
  (`CloudClient.resumeRequest`, the iPad's `resumeRun`), drawn as an answer being written; a stream that
  can't open leaves the thread to be read until the run is done. A message being sent meanwhile is left as it is. A card that no longer waits is read again; one refused for want of the AI-data
  consent stays as it was, with nothing said; anything else, a refusal or an answer that
  doesn't read, says "Your answer didn't reach Setup" (`coach.answer_did_not_reach_setup`). An answer that comes back after sign-out is the
  session before's and is dropped (`gen == accountGeneration`).
- **Read as the iPad reads it:** a card whose `questions`, or any one question, doesn't read
  isn't read at all (`LenientShown`). A recorded answer is the iPad's `CardAnswer`: a `state`,
  `words` or `by` that isn't text leaves it unread; a missing `state` is "answered". This holds
  for every card's answer.
- **An answer sent the old way**, as a message ("[questions <id>] {…}", from before cards recorded
  their answer), is read back as the iPad's `SetupThread.answer(to:)` and `QuestionAnswers.words`:
  with no recorded answer, the person's latest such message after the card, not a failed one, on the
  card's folded line in Coach's labels and their own words ("Test mode · Stripe, Qonto · In your
  words: “…”"); its bubble isn't drawn again (`Thread.Page.oldAnswer`, `answersCard`).
- **Mac differences:**
  - A refusal for want of the AI-data consent keeps the card quietly on both, but the iPad also
    opens its consent screen; the Mac's opens only for a message it sends.
  - The Mac shows each card's own recorded answer. The iPad reads every card under one id
    through `setupThread.answer(to:)`, the last card with that id (`SetupComponent.swift:307-316`).
  - A card's other fields stay as leniently read as every card's on the Mac: a title or text
    that isn't text is left out, not the card.
  - A questions card with an empty list is "0 of 0" and can be sent on the iPad; here it
    shows what it asks.
  - Sign-out moves the conversation on (`signedOut`), so nothing answered after it is kept;
    the iPad also forgets Coach's thread. The window goes then, on the Mac.
  - Haptics and the driven field are the iPad's own.

### The AI-data consent

Before anything a person writes reaches the model, they allow it once. When tafs cloud
refuses a message for want of it (`ai_consent_required`), the app shows **tafs cloud's own
screen**: its title, its lines, Allow and Not now.

- **Allow** sends the version of the words that were read (`POST /v1/me/ai-consent`), then
  the message.
- **Not now** allows nothing and sends nothing more. The message stays unsent.
- **No key allows.** The person has just pressed Return to send their message; Return on the
  consent's screen answers nothing, so consent is always a deliberate click. Esc is Not now.
- A consent without its words is no screen: the refusal is then shown as a failure.

### Files with a message (`ChatFiles`, `FilePrep`, `AttachButton`, `FileTray`, `MessageFiles`)

As the iPad's `AttachViews.swift`, `Services/Attachments.swift`, `AppModel`'s attachments
(`AppModel.swift:4723-4835`) and `TafsCloud`'s routes (`TafsCloud.swift:1059-1110`), in Coach's
chat and a taf's alike:

- **The paperclip**, in the box's foot, offers Choose photos and Choose file, each an open panel
  for as many as the message has room for (5 at most, `FilePrep.perMessage`). With five, it's
  off, and says so. A new conversation that improves a taf takes none: tafs cloud writes its
  first message (`filesTarget`). Nor does a version's trial chat, as the iPad's
  (`trialChats[tafID] == nil`): its paperclip isn't offered.
- **Each file is made ready first:** the kinds tafs takes (photos, PDF, text, CSV, Markdown,
  Word, Excel) under their limits (10 MB a photo, 25 MB a PDF, 2 MB the rest). Every image is
  made a JPEG, its long edge at most 2576 px, drawn again on white so it carries no metadata.
  A file that isn't a photo and is over 25 MB is refused before it's read. Each refusal says
  why above the box, in the shared words.
- **Then it goes up at once:** declared to tafs cloud (`POST /v1/tafs/{id}/attachments` with
  its type, name, size and SHA-256), which checks it and answers where to put it; its bytes go
  straight to storage, with no session (`FileStore`). Each file picked goes up on its own, at
  once. Its chip says Uploading, Ready, or why it didn't upload, with Remove. A session that
  ends while a file is declared puts no bytes up, and one that comes back after sign-out is
  dropped. A photo is read with its orientation applied, and never decoded larger than its
  long edge.
- **Send takes the ready files** with the words, as a message of its own: by id
  (`attachments`), words optional. Send waits while a file is still going up, and while files
  are ready but the chat is at work. A new conversation that improves a taf sends its words alone,
  as the iPad's `improvementHoldsFiles`: its first message carries none, the files wait in the tray for
  the next one, and the box says so ("Files go with your next message: send this one first, then
  attach them."). Send's VoiceOver words say what holds it: "Send once the files are up", "Send when
  this answer is done". A message with files that doesn't go goes
  back to the composer, words and files, with why above the box; one refused for want of the
  AI-data consent goes back too: Allow then only allows, and they wait to send again.
- **A sent message's files** show under it, and each opens: tafs cloud says where it is
  (`GET /v1/tafs/{id}/attachments/{file}`), it's copied under its own name to a temporary
  folder, and shown full size in place, in Quick Look (`quickLookPreview`), as the iPad's. Sign-out
  removes the copies and the files picked; one read after sign-out is neither written nor opened.
- **Take photo** (`CameraSheet`, the iPad's `CameraPicker`), first in the paperclip's menu on a Mac with a
  camera: the system asks the first time, then the camera's picture, **Take photo** and Cancel. The photo goes
  as a chosen one does (`FilePrep.photo`, a JPEG at most 2576 px), named "Photo". Refused at the system's
  question, the sheet closes and nothing is taken. Refused then or before, the tray says where to turn it on,
  in macOS 12's settings and later ones' (`chat.file.mac_camera_off`), and no sheet opens. The camera runs only while the sheet
  shows. It needs the camera entitlement and `NSCameraUsageDescription` (App/tafs.entitlements, App/Info.plist).
- **Mac differences:** chosen photos come from files, so each keeps its own name where the iPad's
  picker gives "Photo {n}"; nothing is dropped onto the box, as on the iPad; a
  file that can't be read says `chat.file.unreadable`, where the iPad shows the system's words.
  The open panel's files are read inside their security scope, as on the iPad, though the app
  isn't sandboxed.

### A drafted door (`DoorDraft`, `DoorDraftCard`)

As the iPad's `DoorDraftCard` (`APIDoorViews.swift:324-418`): a card Coach drafts for a door from
another application (`taf_door_api`, with `taf_id` and `draft_id`) carries no words of Coach's. Its
draft is read from tafs cloud when the card shows (`GET /v1/tafs/{taf}/doors/drafts/{id}`, read
only). It shows:
- "New door · from another application", then the app's name.
- What it can hand the taf (`door.api.draft_scope`) and what the taf does (`door.api.draft_will`).
- The fields it sends, each as its name and its values or type, in a fixed-width face.
- What it gets back (`door.api.draft_back`, the outcomes as a list in the person's language).
- With `text`, the own-words line and its risk, in amber.
- The door's boundary: its key can only hand the taf work, never pay or buy.

A draft tafs cloud says is used (410 `draft_used`) says so in its words, in the ok colour. Any
other failed read says why, in red. Only an API door's draft with a name and a job is drawn; a
field that doesn't read is left out.

**Approve stays the phone's.** Approving opens the door and shows its first key once, which this
Mac doesn't show, as a door's New key. So for whoever manages the taf (`managesTaf`), Approve is a
`GatedAction`: its click says to approve on another device, and nothing is signed or sent. Anyone
else reads the draft alone, as on the iPad.

## Dictating (`Dictation`, `MicButton`, `DictationBar`)

As the iPad's `MicButton.swift` and `Services/Dictation.swift`: the mic in the message bar,
in Coach and in a taf's chat, turns speech into text **into the box**. Nothing is sent by voice:
the words wait until the person sends them, and sending, or leaving the chat, stops dictating.

- **On this Mac only:** recognition must run on the device (`requiresOnDeviceRecognition`),
  so no audio leaves the Mac. The system asks for speech recognition, then the microphone,
  with the iPad's line (`NSSpeechRecognitionUsageDescription`, `NSMicrophoneUsageDescription`
  in `App/Info.plist`, the shared `voice.tafs_turns_your_voice_into`).
- **Into the box:** after what was there, one space between; after a pause the next words go
  after the earlier ones, never over them; a revision of what's being heard replaces it.
  Cancel (the listening bar's ×) puts the box back as it was.
- **When the recognizer ends by itself** it listens again, after what was heard; after three
  ends with nothing heard it stops, quietly after silence, saying why after an error. A restart
  that fails says why.
- **Languages:** the device's on-device languages, the person's preferred first, one form each;
  the chip switches among them and the choice is kept. It starts in the app's language.
- **Hints:** the app's names and the account's tafs, so dictation spells them right.
- **One for the app:** the signed-in window keeps one `Dictation`, as the iPad's
  `AppModel.dictation`. Coach's chat and each taf's chat share it, so only one listens.
- **Refused or unavailable:** the alert says why in the shared words. Where the words name
  Settings, a button opens System Preferences on the right list: Keyboard › Dictation,
  Security & Privacy › Speech Recognition, or its Microphone list.
- **Minimised, or another app in front,** dictation keeps listening, as the iPad's does until
  its chat goes. Leaving the chat stops it.

Mac differences: macOS's permission prompt doesn't hold the window, as the iPad's does, so a
start stopped or left while the system asks starts nothing once it answers. A Mac with no
microphone (no input channels) says dictation couldn't start, where the iPad never needs to.
The Mac has no list of the person's keyboards, so their preferred languages
lead; the box has no insertion point to read, so dictation goes at the end; there is no audio
session to set up, and the microphone is asked through `AVCaptureDevice`; punctuation is added
from macOS 13 (`addsPunctuation`). The shared words name the iPhone's and iPad's Settings paths
("Settings › tafs › Microphone"); Mac words for them come from kiff/tafs.

## The layout

To the iPad's: the screen's name small and centred at the top; the chat on Coach's own wash;
Coach's words at 16; the person's bubble with a continuous corner of 18; a card's choices
as white pills under what it asks (14, padding 14 and 9, edged in ink at 0.18) that **wrap
onto more rows** rather than squeeze; and the message box as a rounded panel (corner 20) at
the foot, its field at 16 and a 40-point send circle, on a bar with a faint shadow upward.
A message still going is at 0.7.

## "Taking shape" (`SetupShape`, `SetupShapePanel`)

As the iPad's `SetupShapePanel` and `SetupShape` (kiff/tafs#85): beside Coach's conversation, 420
wide behind a 1-point rule, once Coach is 780 or wider (dragged wide, or ⤢). The plan then shows
there, not in the conversation.

- Its eyebrow, "Taking shape"; the taf's name once handed over, else the plan's title; with nothing
  yet, "As the conversation goes, the plan, the apps being connected and the taf's Card show here."
- The plan with each step's mark, "Plan · {done} of {total}", and "Needs you" under the step at work
  while a card waits; with no plan, one step for each card that asked something, and where it stands.
- The tools it connects, from planque's grants: each vendor with Connected, Signed in, Waiting for you
  or Not connected (with planque's why), and once connected the tools it brings.
- The Card KIFF drafted, in KIFF's lines, edged dashed until confirmed, with "A draft until you approve it in the conversation."
- **Mac difference:** the iPad shows it once planque is set up on that phone (`planqueReady`), which this
  Mac is only after a Start made on it; here it shows while planque is read for Coach with this Mac's
  proof, as Windows shows it while planque is there to read tools.

## Coach's tools (`CoachTools`, `CoachToolsRow`, `CoachToolsSheet`)

As the iPad's `CoachToolsStep.swift`, from `GET /v1/setup`'s `tools`, read with Coach:

- **The row**, above the conversation, while tafs cloud says the tools aren't given: tafs cloud's line
  ("Coach's tools are waiting for you · Give them"), else "Coach's tools", in amber, with a chevron.
- **The step**, from the row: tafs cloud's title; for `to_give`, its intro, the groups up front, each
  tool (what it does, why) and Coach's Cards in KIFF's words under the step's fold, and its ask; for
  `taken`, which name another tool holds; anything else, that it isn't known. Then **Not now**, which
  only closes it. Every word is tafs cloud's or KIFF's; the app's own stand in only where none came.
- **Give is the phone's:** it signs tafs cloud's batch of connections and Coach's Cards' draft with the
  approval key. Its place says where to approve. No body is kept here, and nothing is sent from it.
- Not here: Start's own screen of the same (`CoachToolsGiven(start: true)`, with Coach's first Start),
  and the step opening by itself after an install or a first Start.

## Not yet

Approving a connection or a Card (the phone's: see above), giving Coach's tools, and Coach mode over a
taf's page. Each is its own pull request; the ones that grant authority come with their approval.

## Tests

`scripts/test.sh coach`: Coach or none, no time zone sent, the thread in tafs cloud's order,
items that don't read, a card's key, an unreadable answer; what is and isn't a message, the
send's exact body, each refusal, the following's pace and its limit, Retry, and both answers
to the consent; a run's work, each kind of card, declining, the live steps, and what `Rich`
reads; an approval's answer, state and lines, `replaced`, KIFF's draft and its lines, the draft read,
a drive's card never a question (`ApprovalTests`); "Taking shape" (`SetupShapeTests`); Coach's tools
(`CoachToolsTests`). It writes `build/screenshots/coach-*.png`, `coach-shape-en.png`,
`coach-replaced-en.png` and `coach-tools-en.png` among them.
