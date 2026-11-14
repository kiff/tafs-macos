# Coach

Coach is where a taf is set up, an app is connected and a taf is changed, in conversation.
**Today this screen reads Coach's chat. Nothing is written or answered from it yet.**

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

## Not yet

Writing to Coach, its answer as it comes, answering a card, connecting an app with its Card,
the list of earlier conversations, and attachments. Each is its own pull request; the ones
that grant authority come with their approval.

## Tests

`scripts/test.sh coach`: Coach or none, no time zone sent, the thread in tafs cloud's order,
items that don't read, a card's key, an unreadable answer, and **that nothing but `GET` is
ever sent**. It writes `build/screenshots/coach-*.png`.
