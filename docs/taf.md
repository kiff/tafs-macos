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
| The head | The taf's coloured square with its initial, and its name. |
| The tabs | **Chat** and **Card**, as the iPad's two-part switch. Activity and Setup are still to come. |
| Chat | The taf's own conversation (`GET /v1/tafs/{id}/conversation`), drawn as Coach's is, with no title of its own. Its box says "Message {taf}", and "Write the next message" while the taf works. Its first Card is beside it, with a button to all its Cards. tafs cloud is never asked which taf is Coach. |
| Card | Each Card's face in the taf's colour: its title, the figure, the first limit for each call ("up to €150 each; more asks you first"), how many tools past one ("no actions yet" with none), and "Until {date}", "Ends · No end date", or "Ended" for a Card no longer active, which is faded. Then a panel of what it lets the taf do: KIFF's label, what happens outside it, and **its limits as the iPad's `CardRule.summary`** (`TafCard.Rule.summary`): each call's, the Card's own total for its window (`base_limit`), the extra room apart, and its calls. The room is apart only beside `base_limit`: without it, `per_window` already holds the room and is said once. **A Card with no rules has no panel**, never an empty one. With no Card, nothing is said: tafs cloud sends no field that says one was revoked. |

- Every word from KIFF or tafs cloud (a name, a title, a label, a window) is drawn as sent,
  with `Text(verbatim:)`.

## Tests

`scripts/test.sh taf`: the Cards as tafs cloud sends them, a Card that doesn't read, a Card
with no rules, the figure from money and from calls, no figure when used is unknown or the
units differ, a used over the limit, and money in its language. On a Mac: a taf's chat reads
that taf's conversation without asking which taf is Coach, a Card with no rules has no panel
under it, and the screenshots `build/screenshots/taf-<tab>-<language>.png`.
