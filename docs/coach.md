# Coach

Coach is where a taf is set up, an app is connected and a taf is changed, in conversation.
**Today this screen reads Coach's chat and writes to Coach. Its cards can't be answered from it yet.**

## What is read (`Coach`, `Thread`, `CloudClient`)

| Call | Route | What |
|---|---|---|
| `coach()` | `GET /v1/setup` | The account's Coach, or none before Coach is started. A plain read: unlike the phones' first read it sends no time zone, so it changes nothing on the account. |
| `thread(of:)` | `GET /v1/tafs/{id}/conversation` | The chat as one ordered list (`items`): messages, cards and held calls by time. |

The app draws the list as it comes. It places and folds nothing itself.

| Item | Drawn as |
|---|---|
| A message from the person | Their words, on Coach's blue, at the right |
| A message from Coach | Its words, at the left. Plain text: the model's words are never read as formatting or as a line of the app's. |
| A job's instruction (`kickoff`) | A small note |
| A card that waits for the person (`waits: owner`) | "Needs you · a question" |
| A card tafs cloud answers itself (`waits: service`) | Nothing |
| A call KIFF held | "Needs you · approve". It is answered in Needs you. |
| Anything else (a drive's end, a kind this app doesn't know) | Nothing |

- A card is known by its `key`, which is unique in the thread, never only by the name the
  model gave it: the model may reuse a name.
- An item that doesn't read is left out. An answer with no ordered list is unreadable, never
  an empty chat.
- With no Coach, or an empty chat: "Ask anything about your tafs".

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

## Not yet

Coach's answer as it is written (the stream), answering a card, connecting an app with its Card,
the list of earlier conversations, and attachments. Each is its own pull request; the ones
that grant authority come with their approval.

## Tests

`scripts/test.sh coach`: Coach or none, no time zone sent, the thread in tafs cloud's order,
items that don't read, a card's key, an unreadable answer; what is and isn't a message, the
send's exact body, each refusal, the following's pace and its limit, Retry, and both answers
to the consent. It writes `build/screenshots/coach-*.png`.
