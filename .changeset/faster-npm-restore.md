---
"@dryfit/cli": patch
---

Restoring an npm app is faster. With a `node_modules` in place, `dryfit restore` now runs `npm install`, which changes only the dev builds, instead of `npm ci`, which deletes `node_modules` and installs everything. On a sample app that took 0.35 s instead of 1.5 s, and the gap grows with the app. If the incremental install fails, the full `npm ci` runs, and a lockfile that npm rewrote goes back to the snapshot's bytes, so the restore stays exact.
