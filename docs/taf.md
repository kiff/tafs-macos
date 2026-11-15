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
| Each thing it lets the taf do | `rules[]`: `label`, `outside`, `count_per_window`, `window_words.each` | KIFF's words for it; `refused` or `held` for a call outside it; its limit and tafs cloud's words for the window. A Card may have no rules. |
| Its money | `total`: `limit` and `used`, each `{minor, unit, scale}`, and `window_words.now` | |
| Its calls | `calls`: `limit`, `used`, and `window_words.now` | |

- **The figure** (`TafCard.figure`) is what is left: of the money when the Card has a total,
  else of its calls. Never below zero.
- **No figure is ever a guess.** With no `used` (KIFF couldn't read it), or a limit and a
  used in different units or scales, there is no figure.
- **Money** is written as the app's language writes it (`Amount.written`): "€1,960",
  "€12.50". Whole amounts lose their zeros, as the apps write money everywhere. A unit that
  isn't a currency's code follows the number as written.

## Tests

`scripts/test.sh taf`: the Cards as tafs cloud sends them, a Card that doesn't read, a Card
with no rules, the figure from money and from calls, no figure when used is unknown or the
units differ, a used over the limit, and money in its language.
