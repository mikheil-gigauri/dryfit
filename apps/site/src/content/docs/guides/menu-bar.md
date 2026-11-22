---
title: Menu bar app
description: dryfit on macOS without a terminal, from the menu bar and its own window.
---

On macOS, dryfit has an app: a menu in the menu bar for what you do all day, and a window for setting
things up. Everything the CLI does day to day can be done there, without a terminal. It needs macOS 26
or newer and talks to the same background service as the CLI, so you can use both.

![The dryfit window: @acme/ui linked into shop (npm) and admin (pnpm), with its build settings below](/dryfit/menu/window-library.light.png)

## The window

Open it from the menu with **Open**. The first time the app starts, it opens by itself and walks you
through three steps: choose the folders where your apps live, add a library, and link it to an app.

- **Add library** (the **+** button at the bottom of the sidebar, or ⌘O) asks for the library's folder,
  then shows how dryfit will build it and which folder it publishes. Change either before adding it,
  or later with **Change…**. [Build and publish settings](/dryfit/guides/libraries/) explains what to
  choose.
- A library's page lists the apps it is linked into, with the version each one runs, and below them the
  apps in your project folders that use the library, each with a **Link** button. **Choose app…** links
  an app from anywhere else.
- **Apps** in the sidebar lists every app that uses one of your libraries, found in your project
  folders. An app's page shows each of those libraries as a **Dev build** or a **Release**, with
  **Link** for the ones still on their release. **Add App…** (⇧⌘O) adds an app from outside your
  project folders. You can also drop a folder on the window: an app opens its page, a library opens the
  form that adds it.
- Drag libraries, apps and groups in the sidebar to put them in your own order, or use **Move Up** and
  **Move Down** in a row's context menu (⌥⌘↑ and ⌥⌘↓ for the open row). The menu lists them, and the
  apps under each library, in that same order. ↑ and ↓ move through the sidebar.
- **Hide App** in an app's row context menu, or the hide button at the bottom of its page, stops listing an app you
  don't work on. Nothing in the app changes, and **Settings** lists hidden apps with **Show** to bring
  one back. A linked app has to be restored first.
- **Sync now** builds, publishes and installs into every linked app. Turn on **Auto-sync** to do that
  every time you save a change in the library.
- **Restore** on a linked app puts that app back on the release of that one library and keeps its
  other libraries linked. **Restore all** on an app's page puts every library back. When the app's
  `package.json` changed after linking, dryfit asks before overwriting the change.
- **New Group** (⇧⌘N) saves apps you test together, so a library can be linked into, or restored from,
  all of them at once.

## The menu

![The dryfit menu: a failed install at the top, two libraries with their linked apps, and a group](/dryfit/menu/online.light.png)

From the menu you can:

- turn Auto-sync on or off for each library, or sync it once, and watch a sync's progress on its card;
- link a library to the apps that use it with one click, from the chips under it, or to any other
  app with **Other…**;
- restore an app with the arrow at the end of its row, also after a failed install;
- fold a library's card with its arrow to keep the menu short;
- see each app's installed version, and why an install failed, with the full output a click away;
- link and restore saved groups, and see when a group's apps disagree on a version;
- start or stop dryfit, and open its log.

It also tells you, in a notification, when an install fails while the menu is closed.

Right-click (or Control-click) the menu bar icon for **Settings…**, the log, **Open at Login**,
**Check for Updates…**, starting or stopping dryfit, and quitting.

## Settings

**Settings** is a page of the window: open it with the gear at the bottom of the sidebar, with ⌘, or
from the menu bar icon's right-click menu. It holds the folders dryfit searches for apps, the apps you
hid, dryfit's service with its log and **Start dryfit at login**, **Open at login**, and updates.

**Open at login** opens the app, but does not start dryfit itself. Turn on **Start dryfit at login**
(the same as `dryfit daemon install`) so auto-sync is running again after a restart.

## Install

The app needs macOS 26 or later. [Download Dryfit.dmg](https://github.com/mikheil-gigauri/dryfit/releases/latest/download/Dryfit.dmg),
open it and drag **Dryfit** to **Applications**.

The app is not notarized by Apple yet, so the first time you open it macOS says it cannot check it and
offers only **Done** and **Move to Trash**. Choose **Done**, open **System Settings → Privacy & Security**,
and under Security choose **Open Anyway** for Dryfit. macOS remembers the choice, and the updates the
app installs itself do not ask again. To do the same from a terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Dryfit.app
```

The app runs dryfit's command-line tool in the background. If it is not installed, the app offers to
install it with npm (`npm install --global @dryfit/cli`), which needs Node.js.

## Updates

Install the app once, and it keeps itself up to date. Once a day it looks for a new version, downloads it in
the background, and replaces and reopens itself the next time you are not using it. Your libraries, apps
and links are untouched: they live in dryfit's service, which keeps running.

The app updates only itself. dryfit's command-line tool, which runs the service, comes from npm, so when
it is older than the app, the menu says so and offers **Update**: it runs
`npm install --global @dryfit/cli@latest`, then restarts dryfit on the new version. Your libraries,
links and watches carry over. Settings shows the same.

To choose when, turn off **Install updates automatically** in Settings: the app then asks before
installing. **Check for Updates…** in the icon's right-click menu looks right away. Versions from before 0.3.0 do not
update themselves, so download the newest version once more.
