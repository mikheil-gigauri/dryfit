---
title: Troubleshooting
description: What to do when a change does not show up, an install fails, or dryfit will not start.
---

Start with `dryfit doctor`. It checks Node, npm, your config and project roots, and the service, and says
what to fix. `dryfit events` follows what the service does while you reproduce a problem, and the service's log is at
`~/.dryfit/logs/daemon.log`.

## My change does not show up

Check that the install reached the app: `dryfit status` lists each linked app with the version it has.
If the version is right, the app's dev server is still serving the old build: restart it. If the app uses
a build cache dryfit does not know about, delete that folder too.

If the version is not right, the build or the install failed. `dryfit status` shows the failure, and the
menu bar app shows its full output.

## An install fails with a peer dependency error

The dev build declares the same peer dependencies as the release, so an install that fails now usually
fails for the release too. npm's `ERESOLVE` errors are often fixed by the app's own `.npmrc`
(`legacy-peer-deps=true`) if that is how the project is meant to install.

When the conflict is between libraries from your own workspace that pin each other exactly, link them
together instead: `dryfit link <app> --library <a> --library <b>`. The failure message names the ones
to add. See [Libraries that pin each other](/dryfit/guides/libraries/#libraries-that-pin-each-other).

## pnpm refuses the dev build

`ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION` comes from a `pnpm install` run by hand while the app is linked.
dryfit's own installs lift that limit; yours do not. Run `dryfit sync`, or restore the app first.

## "Unsupported package manager"

dryfit supports npm, pnpm, Yarn 2 or newer, and Bun with a text lockfile. Yarn 1 projects cannot be
linked, and Bun projects with only a binary `bun.lockb` need `bun install --save-text-lockfile` once.

## The ports are taken

dryfit uses `127.0.0.1:4874` for its registry and `127.0.0.1:4875` for the service. To use others, set
`ports` in `~/.dryfit/config.json` and restart:

```json
{ "roots": ["/Users/you/code"], "ports": { "api": 4885, "registry": 4884 } }
```

```bash
dryfit daemon restart
```

## An app is still linked after I deleted dryfit's state

Restoring needs the snapshot in `~/.dryfit/snapshots`. Without it, put the app back with git:

```bash
git checkout -- package.json package-lock.json && npm ci
```

Use your own lockfile name and install command, and delete `.git/hooks/pre-commit` if dryfit created it.
