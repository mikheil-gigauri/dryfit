---
title: Package managers
description: How dryfit installs into npm, pnpm, Yarn and Bun projects, and what each one needs.
---

dryfit installs into each app with the package manager that app already uses. It decides which one from
the `packageManager` field in `package.json`, or else from the lockfile. Your library can use a different
package manager from your apps: dryfit always publishes with npm.

| App uses        | Lockfile            | How the dev build is installed                         |
| --------------- | ------------------- | ------------------------------------------------------ |
| npm             | `package-lock.json` | By version, with the library's scope pointed at dryfit |
| pnpm            | `pnpm-lock.yaml`    | By version, with the library's scope pointed at dryfit |
| Yarn 2 or newer | `yarn.lock`         | From the dev build's tarball URL                       |
| Bun             | `bun.lock`          | From the dev build's tarball URL                       |

dryfit never edits your `.npmrc`, `.yarnrc.yml` or `bunfig.toml`. Restoring puts `package.json` and
the lockfile back exactly as they were, and removes a lockfile the app did not have before.

## npm and pnpm

The dev build is installed as an exact version, with the library's scope pointed at dryfit for that one
command. Every other package still comes from your own registry.

Recent versions of pnpm hold back versions published less than a day ago (`minimumReleaseAge`). A dev build is
always minutes old, so dryfit lifts that limit for its own install. A plain `pnpm install` you run
yourself while the app is linked still applies it and refuses the dev build. Run `dryfit sync` instead,
or restore the app first.

## Yarn

Yarn reads registries per scope only from `.yarnrc.yml`, so dryfit installs the dev build from its
tarball URL instead, for example
`http://127.0.0.1:4874/@acme/ui/-/ui-1.4.1-dev.20261119143201.tgz`. Your `package.json` holds that URL
until you restore. Installing from a URL also avoids Yarn's release-age gate, which applies to registry
versions only.

Yarn 1 is not supported: dryfit says so instead of installing.

## Bun

Bun does not let a command override the registry for a scope, so it is installed from the tarball URL, as
with Yarn. Bun projects need the text lockfile, `bun.lock`. For an older project that still has the binary
`bun.lockb`, switch once:

```bash
bun install --save-text-lockfile
```

## Workspaces

A library whose `package.json` uses `workspace:` or `catalog:` ranges cannot be published as it is,
because those ranges only mean something inside its own workspace. Build tools such as ng-packagr write a
publishable `package.json` into the output folder; point dryfit at it with
`dryfit add --publish-dir dist/ui`.
