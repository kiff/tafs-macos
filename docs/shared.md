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

## Contracts

kiff/tafs keeps what tafs cloud answers the apps as fixtures in `contracts/`, written by tafs
cloud's own tests. `scripts/test.sh contracts` reads them with this app's decoders
(`Sources/Core/contracts`), so an answer whose shape changed fails here in CI, never first on
someone's Mac.

| Fixture | Read by | State |
|---|---|---|
| `ai-consent.json` | `TafsCloud.AIConsent`, `TafsCloud.Refusal` | read |
| `setup-start.json`, `setup-start-draft-alone.json`, `setup-time-zone.json` | Coach's first start | with the Coach screens |
| `recipes-home.json` | Home's recipes | with the Overview |

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
