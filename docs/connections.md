# Connect apps

The account's own connections, then the catalog of apps a taf can use. **This screen lists.**
An app is connected through Coach, where its Card is approved with it; that flow arrives
with Coach.

## What is read (`Apps`, `CloudClient.apps(_:cursor:)`)

`GET /v1/connect/apps?q=&cursor=` on tafs cloud.

| Drawn | From |
|---|---|
| The row's name | `name` (an older tafs cloud's `title`). Never `vendor`, which is a key. |
| What this entry of the app is | `subtitle` |
| The second line: how it connects, its status, which tafs use it | `line`, as sent; for an app an operator sets up first, its `words` |
| "Company" or "Yours" | `whose`, as sent |
| How it connects | `method`, else `how`, through the shared lines `connect.how.*` |
| Which tafs use it | `used_by[].name`, through `connect.apps.used_by`; a user that doesn't read is left out |
| Which list it is in | `state`: `connected` and `needs_reconnect` are **Yours**, the rest **Discover** |

- A connection to sign in again has its line in amber.
- A row this app can't read is left out. An answer with no list is unreadable, never "No app
  by that name."
- `partial` says tafs cloud's read stopped early: then "No app by that name." is not shown,
  since an app that isn't listed isn't absent.

## The screen (`ConnectAppsView`, `ConnectAppsModel`)

Laid out as the iPad's: the large title with the search box at its top right, then two
panels.

- **Yours** is a table with the iPad's columns (`ConnectColumns`: the app at least 200 wide,
  How 150, Whose 130, Status 230, 12 apart): **App** (its initial's square, its name and what
  this entry is), **How it connects** ("With a key" when tafs cloud's `method`, or an older
  one's `how`, is `key`; else "Sign in", as the iPad decides it), **Whose** (`whose`, as
  sent), and **Status**: "Connected" in green or "Sign in again" in amber, with **"Used by
  …"** under it, the names in `used_by` as the language lists them.
- **Discover** lists the other apps in the same columns, with the headings over it when
  there is no Yours. An app an operator sets up first is named in the soft colour, with tafs
  cloud's `words` in its Status cell.

- Search by name; Return searches. What is typed is escaped and cut at 100 characters.
- **Show more apps** reads the next page of the same search. An app already listed isn't
  listed twice.
- A slower answer to an older search is dropped.

## Not yet

Connecting, signing in again, removing access, the app's logo, and a connection's detail.
Each of the first three changes what a taf may do, so each comes with its approval.

## Tests

`scripts/test.sh connections`: the catalog as tafs cloud sends it, rows that don't read, the
two lists, a search's escaping and limit, paging without repeats, an unreadable catalog, and
**that nothing but `GET` is ever sent**. It writes `build/screenshots/connect-apps-*.png`.
