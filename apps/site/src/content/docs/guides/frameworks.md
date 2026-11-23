---
title: Frameworks and caches
description: Which build caches dryfit clears after an install, and when to restart your dev server.
---

Several build tools keep a prebuilt copy of your dependencies and serve it until they notice a change.
A new version in `node_modules` is not always noticed, so after every install dryfit deletes the caches
it knows about in that app:

| Detected from                           | Cache cleared                                             |
| --------------------------------------- | --------------------------------------------------------- |
| `angular.json` or `@angular/core`       | `.angular/cache`, or `cli.cache.path` from `angular.json` |
| `@angular-architects/native-federation` | `node_modules/.cache/native-federation`                   |
| `vite`                                  | `node_modules/.vite`                                      |

dryfit only ever deletes folders inside the app.

## Restart the dev server

A running dev server holds the old build in memory. After a sync, restart it unless it reloaded on its own.
`dryfit events` and the menu bar show when each install finished. The menu bar marks an app only while a
node, bun or deno process serving it (such as `ng serve`, `vite` or `next dev`) has been running since before
the install, and clears the mark once that process restarts or stops.

## Apps that run together

A Native Federation or Module Federation shell and its remotes each install the library separately. If
they end up on different dev versions, the shared copy may not be the one you just built. Save them as a
group so they are linked, synced and restored together:

```bash
dryfit group save checkout ../shell ../cart ../payments
dryfit link --group checkout
```

`dryfit status` and the menu bar warn when the apps in a group have different versions of the same
library.
