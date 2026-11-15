# The shared words and contracts

Every tafs app says the same thing with the same words. They are written once, in
[kiff/tafs](https://github.com/kiff/tafs), and this app reads them from there at one commit:
the **pin**, in `shared.pin`. Nothing is translated, worded or copied by hand in this
repository.

## What is read

| From kiff/tafs | What | Used by |
|---|---|---|
| `app/strings/<lang>/*.json` | The apps' own words, in 8 languages | `Words` (`Sources/Core/strings`) |
| `app/strings/languages.json` | The languages the apps ship | `Words.shipped` |
| `contracts/*.json` | What tafs cloud answers the apps | the `contracts` tests |

`scripts/shared.sh fetch` puts them in `.shared/`, which git ignores. The tests run it first.

## Using a line

```swift
words("home.overview.title")                          // "Overview"
words("home.not_fully_removed", ["name": taf.name])   // a value, by its name
words.count("needs_you.count", 3)                     // the plural form of 3 in the language
```

- **A value** fills its `{name}`. `{name|possessive}` gets the language's possessive, by the
  same rule as kiff/tafs's generator: English and German have one, the others keep the name.
- **A count** takes the plural form of its number in the language (Polish has `one`, `few`
  and `many`), or `other` when the line has no such form.
- **The app's language** is the first one the person prefers that is shipped, else English.
- **A key the code names must exist.** A test reads every `words("…")` and `words.count("…")`
  in `Sources/` and fails for a key English lacks, or a count used as a plain line.

## A refusal's why

When tafs cloud refuses, the person reads what the iPad's `CloudError` says
(`ios/Tafs/KIFF/TafsCloud.swift:9-49`): tafs cloud's `words`, else its `error`, else
`error.cloud_answered` ("tafs cloud answered 409"). Its `code` is never shown on its own: it
only decides what the app does (the AI-data consent, a halt). `CloudRefusal.why` says it, and
every screen's line for a refusal goes through `NeedsYouModel.why`. A model has no view to
hand it the words, so it reads `Words.app`, set once at launch.

## Ids in a path

An id in a tafs cloud path (`/v1/tafs/{id}/…`, a card's, a session's, what a case is about)
is escaped as the iPad's `escaped` (`TafsCloud.swift:2825-2827`): what a path allows stays as
it is (`taf-1`, `a.b`, `x_y`, `me@acme`), and only `/` and what a path can't carry are
escaped. tafs cloud matches the path as it is sent, so `taf-1` must reach it as `taf-1`,
never `taf%2D1`. `CloudClient.escaped` does it; `CloudClient.query` is for a query's values
only.

## Contracts

kiff/tafs keeps what tafs cloud answers the apps as fixtures in `contracts/`, written by tafs
cloud's own tests. `scripts/test.sh contracts` reads them with this app's decoders
(`Sources/Core/contracts`), so an answer whose shape changed fails here in CI, never first on
someone's Mac.

| Fixture | Read by | State |
|---|---|---|
| `ai-consent.json` | `TafsCloud.AIConsent`, `TafsCloud.Refusal` | read |
| `setup-start.json`, `setup-start-draft-alone.json`, `setup-time-zone.json` | Coach's first start | with the Coach screens |
| `recipes-home.json` | `HomeWords`: tafs cloud's line for an account with no taf | read |
| `taf-activity.json`, `taf-setup.json`, `taf-setup-connected.json`, `taf-setup-reconnect.json` | A taf's Activity and Setup tabs | with the taf page |
| `home.json`, `home-paused.json` | `Home.Page`: the tafs the sidebar and the Overview list, live and paused, with each one's state, work line, health and Cards | read |
| `tafs.json`, `tafs-paused.json` | `GET /v1/tafs`: each taf's schedule and time-zone words | with the screens that show them; the tafs list is `home.json` |
| `taf-runs.json`, `taf-run-report.json`, `taf-run-report-running.json`, `taf-run-report-terminated.json` | The Overview's Last result | read |

A fixture that is in kiff/tafs and in neither list of `Tests/contracts/ContractTests.swift`
fails the tests: a new contract is read, or its screen is named. The contracts run on every
pull request, whatever it changes.

## A new line

It goes into kiff/tafs first, in every language. Then the pin moves to a commit that has it.
A line is never written in this repository's code.

## Moving the pin

Put kiff/tafs main's commit in `shared.pin`, in a pull request with nothing else. Every part's
tests run on it.

## The drift check

`scripts/shared.sh drift` fails when kiff/tafs main is **more than 20 commits** past the pin,
or when the first commit past it is **more than 7 days** old. CI runs it on every pull request
and each night.
