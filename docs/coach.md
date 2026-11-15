# Coach

Coach is where a taf is set up, an app is connected and a taf is changed, in conversation.
**Today this screen reads Coach's chat, writes to Coach, and answers its choices. Its approvals can't be given from it yet.**

## What is read (`Coach`, `Thread`, `CloudClient`)

| Call | Route | What |
|---|---|---|
| `coach()` | `GET /v1/setup` | The account's Coach, or none before Coach is started. A plain read: unlike the phones' first read it sends no time zone, so it changes nothing on the account. |
| `thread(of:session:)` | `GET /v1/tafs/{id}/conversation[/{session}]` | The chat as one ordered list (`items`): messages, cards and held calls by time; with a session, that chat's alone. |
| `chats(of:)` | `GET /v1/tafs/{id}/chats` | Coach's chats (`session`, `started`, `updated`, `title`), each one strictly. |

The app draws the list as it comes. It places and folds nothing itself.

| Item | Drawn as |
|---|---|
| A message from the person | Their words on the brand's gradient, at the right. A time, centred, on the first item and after an hour's gap |
| A message from Coach | "Worked for 32 s", which opens the run's steps folded as the iPad's (`WorkRows`); then its words, with no bubble |
| A job's instruction (`kickoff`) | A small note |
| The plan (`steps`) | tafs cloud's `line` and the step in hand with its mark; opened, every step with its mark, the one in hand semibold, a skipped one struck through |
| A choice (`confirm`) | What it asks, then a white pill for each answer. Answered: one folded line, "{question} · {chosen}" |
| Questions (`questions`) | The iPad's `QuestionsCard`: Coach's words, its title as an eyebrow with "{n} of {total} answered", each question numbered with its options and **Something else…**, then **Send answers** and **Chat about this**. Answered: one folded line, "Your answers · {tafs cloud's words}" |
| An approval that waits | Edged in amber: "Needs you · approve", what it asks, **Decline**, and where to approve |
| A sign-in that waits | Edged in amber: "Needs you · sign in", "Sign in at {app}", its note, where to sign in, and **Not now** |
| An approval already answered | One folded line, ticked in green with tafs cloud's line for the connection; a decline ("Declined · {title}") with a grey minus |
| A note (`notice`) | A panel in its tone's colour, its title in that colour |
| The hand-over (`result`) | Edged in green: "Set up · the taf's name", what it does, its tools, and **See it on {taf}** once the taf is listed ("Setting up {name}…" until then). Failed: "{name} wasn't set up: {why}." and no button. Needing a plan: **Choose a plan**, to Plan & usage |
| A call KIFF held | "Needs you · approve". It is answered in Needs you. |
| Anything else (a drive's end, a kind this app doesn't know) | Nothing |

- **A run's steps** are tafs cloud's words for them, never a tool's name: a tick, a red mark
  for a failure, an arrow for one not made ("not made · read first"), and "{n} tries".
- **Coach's words are drawn as the iPad's `MarkdownText`**: no Markdown mark shows, a link is
  its label only, and every piece is `Text(verbatim:)`. A ``` fenced block is its lines as
  written, no mark read inside, in 14 mono on the raised ground (padding 10, radius 8); one
  never closed is code to the end, as while an answer streams. The plan stays where it was shown.
- **Approve is not on the Mac yet.** The card says where to approve. **Decline** and **Not
  now** answer it with `declined` or `not now`, and grant nothing.
- **A decline** is known only by tafs cloud's words for the answer, which it writes in the
  app's language: "Declined". An approval or sign-in answered another way (`wrote`,
  `no_answer`) draws nothing.
- **See it on** opens the taf's own page, or the Overview when the list doesn't have it.
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
| An answer | the card's `answer.state` and `words` | Shown as answered only when the person chose (`answered`). One they wrote past (`wrote`) or that stopped waiting (`no_answer`) waits no more, and shows no answer. |
| A connection already made | an approval component's `connection`, when `done` | tafs cloud's line for it. |
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
  it opened over; on the right, New conversation (the pencil, which does nothing on an empty
  chat) and the conversations' menu, with Previous conversations.
- **The sidebar's Coach** only opens Coach, as `openCoach`. Coach closes from its own Back.
- **Previous conversations** lists Coach's chats (`GET /v1/tafs/{id}/chats`) as tafs cloud
  lists them: each by its title and when it was last written to, the one shown marked. One
  click reopens it: what was on its way belonged to the chat before (a consent ask with it),
  and the chat is read by its session. A list read that fails keeps the list as it was. A
  reopen whose read fails keeps the page shown, with "The conversation couldn't be loaded: …" and
  Try again under it, as `loadSetupThread`'s `setupError`. Done (Esc) closes it.
- **After sign-out**, a chats list or a reopened chat that comes back late is dropped, as the
  iPad's `accountGeneration` guard.
- **Start a new taf**, from Home's Own words, the gallery's own words, and the sidebar's +
  when tafs cloud sends no gallery (`HomeSplitView.swift:434-438`; with one, + opens it, see
  `docs/overview.md`), opens a new conversation in Coach, so Coach mode's start shows, whether
  Coach was open or not. Asked before Coach is read, Coach opens on a new conversation once it is.

### Mac differences

- **Back doesn't return to a taf page.** Back goes to the screen Coach opened over; opening
  Coach closes a taf's page first, so Back from there lands on the screen under it.

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
| `text` | Adds to the answer, drawn under the person's message. |
| `state`, `activity` | The one line of where the run is, in tafs cloud's words; "Thinking…" before either. |
| `step` | If it failed, tafs cloud's one line of why, under the answer. |
| `held`, `taken`, `component`, `part` | The thread now has something the stream doesn't carry: it is read again. |
| `end` | The answer is over: the thread is read, which has it whole. If the run stopped with a reason, tafs cloud's words for it are shown. |
| `thinking` | Nothing. The model's thinking is never drawn. |

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
  the one shown from then on, for a new conversation (`settleSetupChat`). Then the thread is
  followed. A card that no longer waits is read again; one refused for want of the AI-data
  consent stays as it was, with nothing said; anything else, a refusal or an answer that
  doesn't read, says "Your answer didn't reach Setup" (`coach.answer_did_not_reach_setup`). An answer that comes back after sign-out is the
  session before's and is dropped (`gen == accountGeneration`).
- **Read as the iPad reads it:** a card whose `questions`, or any one question, doesn't read
  isn't read at all (`LenientShown`). A recorded answer is the iPad's `CardAnswer`: a `state`,
  `words` or `by` that isn't text leaves it unread; a missing `state` is "answered". This holds
  for every card's answer.
- **Mac differences:**
  - The iPad reads an answer sent the old way, as a message, back into words
    (`QuestionAnswers.words`); the Mac shows tafs cloud's words for the recorded answer only.
  - A refusal for want of the AI-data consent keeps the card quietly on both, but the iPad also
    opens its consent screen; the Mac's opens only for a message it sends.
  - The Mac shows each card's own recorded answer. The iPad reads every card under one id
    through `setupThread.answer(to:)`, the last card with that id (`SetupComponent.swift:307-316`).
  - The iPad follows the answered run's stream (`followAnswered`); the Mac reads the thread
    until the run is done, as it does after every card's answer.
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

## The layout

To the iPad's: the screen's name small and centred at the top; the chat on Coach's own wash;
Coach's words at 16; the person's bubble with a continuous corner of 18; a card's choices
as white pills under what it asks (14, padding 14 and 9, edged in ink at 0.18) that **wrap
onto more rows** rather than squeeze; and the message box as a rounded panel (corner 20) at
the foot, its field at 16 and a 40-point send circle, on a bar with a faint shadow upward.
A message still going is at 0.7.

## Not yet

Approving a connection or a Card,
archiving a conversation and the archived ones (Previous conversations' swipe and
Archived), Coach mode over a taf's page, and attachments. Each is its own pull request; the ones
that grant authority come with their approval.

## Tests

`scripts/test.sh coach`: Coach or none, no time zone sent, the thread in tafs cloud's order,
items that don't read, a card's key, an unreadable answer; what is and isn't a message, the
send's exact body, each refusal, the following's pace and its limit, Retry, and both answers
to the consent; a run's work, each kind of card, declining, the live steps, and what `Rich`
reads. It writes `build/screenshots/coach-*.png`.
