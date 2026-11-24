---
title: Getting started
description: From nothing to a library change running inside your app, and back.
---

You need Node 22.12 or newer, macOS or Linux, and an app that installs your library with npm, pnpm, Yarn 2
or newer, or Bun.

## Install dryfit

```bash
npm install --global @dryfit/cli
```

This puts `dryfit` on your PATH for the commands below. To try it without installing anything, use
`npx @dryfit/cli` wherever this guide says `dryfit`.

## Start dryfit

Run this in the folder of the library you are working on:

```bash
dryfit init
```

`init` remembers where your projects live and starts dryfit's background service. By default, that is the
folder above the one you are in: for a library in `~/code/ui`, dryfit looks through `~/code`. If your apps
live somewhere else, pass `--root` once for each folder:

```bash
dryfit init --root ~/code --root ~/work
```

Nothing in your projects changes yet. dryfit keeps its own state in `~/.dryfit`.

## Register the library

```bash
dryfit add
```

dryfit works out how the library is built and which folder gets published. It recognises Nx and Angular
CLI libraries and packages with a `build` script. When it cannot tell, set them yourself with `--build "<command>"` and
`--publish-dir <dir>`. [Build and publish settings](/dryfit/guides/libraries/) explains which folders to
choose.

## Find the apps that use it

```bash
dryfit consumers
```

This lists every project under your roots that depends on the library, with its name and folder. It only
reads: nothing changes yet.

## Link an app

```bash
dryfit link shop
```

Name the app as `dryfit consumers` lists it, or give its folder, such as `../shop`. A folder is relative to
where you run the command.

Linking is the first time dryfit changes anything in the app. It saves a copy of the app's `package.json` and
lockfile, installs a dev build of the library the way a release would be installed, clears the framework
caches that would hide it, and adds a [commit guard](/dryfit/guides/commit-guard/) so the dev build
cannot be committed by accident.

To check that it worked, `dryfit status` shows every link and the dev version each app runs.

## Work

```bash
dryfit watch
```

Every time you save, dryfit builds the library, publishes a new dev version such as
`1.4.1-dev.20261119143201`, and installs it into every linked app. When it clears an app's framework
caches, it tells you to restart that app's dev server: one that is running keeps serving the old build
until then. An Angular app needs that restart only once, after linking
([Frameworks and caches](/dryfit/guides/frameworks/)).

`watch` prints what dryfit does as it happens. Ctrl-C stops the printing, not the watching: dryfit keeps
installing every save until you run `dryfit unwatch`. To build and install just once, run `dryfit sync`.

## Put the app back

```bash
dryfit restore shop
```

The app's `package.json` and lockfile are written back exactly as they were, its dependencies are
reinstalled from them, and the commit guard is removed. `restore --all` does every linked app at once.

If you changed the app's `package.json` while it was linked, restore stops instead of losing your change.
Commit or stash it first, or run `dryfit restore shop --force` to overwrite it.

## Keep it running

`dryfit daemon install` starts dryfit when you log in (macOS only for now). On macOS, the
[menu bar app](/dryfit/guides/menu-bar/) gives you the same controls without a terminal.
