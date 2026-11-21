---
"@dryfit/cli": patch
---

A CLI no longer restarts a newer dryfit daemon that speaks the same API. Before, two CLI versions used side by side, such as a global install and `npx @dryfit/cli@latest`, restarted the daemon on every switch and cancelled the job it was running. An older daemon is still replaced, so an update takes effect, and `dryfit doctor` says when a newer daemon is kept.
