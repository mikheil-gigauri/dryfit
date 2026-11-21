---
"@dryfit/cli": patch
---

Commands start about five times faster. The CLI used to load the registry (Verdaccio, about 300 ms) on every command, even `--version`; now only the daemon does. `dryfit --version` takes about 60 ms instead of 300 ms.
