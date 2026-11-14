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
| Which list it is in | `state`: `connected` and `needs_reconnect` are **Yours**, the rest **Discover** |

- A connection to sign in again has its line in amber.
- A row this app can't read is left out. An answer with no list is unreadable, never "No app
  by that name."
- `partial` says tafs cloud's read stopped early: then "No app by that name." is not shown,
  since an app that isn't listed isn't absent.

## The screen (`ConnectAppsView`, `ConnectAppsModel`)

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
