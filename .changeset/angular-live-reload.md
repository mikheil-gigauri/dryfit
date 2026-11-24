---
"@dryfit/cli": minor
---

Angular apps pick up each sync without restarting the dev server. While an app is linked, dryfit keeps linked libraries out of the dev server's pre-bundle (`prebundle.exclude` in `angular.json`), so `ng serve` rebuilds and reloads the page after every install. Restart the dev server once after linking; after that, syncs need no restart and dryfit no longer asks for one. `dryfit restore` puts `angular.json` back, and the commit guard refuses to commit the setting.
