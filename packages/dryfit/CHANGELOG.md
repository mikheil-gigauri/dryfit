# @dryfit/cli

## 0.8.2

### Patch Changes

- 8422ab7: Restoring an npm app is faster. With a `node_modules` in place, `dryfit restore` now runs `npm install`, which changes only the dev builds, instead of `npm ci`, which deletes `node_modules` and installs everything. On a sample app that took 0.35 s instead of 1.5 s, and the gap grows with the app. If the incremental install fails, the full `npm ci` runs, and a lockfile that npm rewrote goes back to the snapshot's bytes, so the restore stays exact.
- c73e2c1: A CLI no longer restarts a newer dryfit daemon that speaks the same API. Before, two CLI versions used side by side, such as a global install and `npx @dryfit/cli@latest`, restarted the daemon on every switch and cancelled the job it was running. An older daemon is still replaced, so an update takes effect, and `dryfit doctor` says when a newer daemon is kept.
- b46fd8b: Commands start about five times faster. The CLI used to load the registry (Verdaccio, about 300 ms) on every command, even `--version`; now only the daemon does. `dryfit --version` takes about 60 ms instead of 300 ms.
- ab33209: The menu bar app's window and widget are rebuilt to match the approved design exactly. The window has no title bar, so its buttons sit over a sidebar that is always there, with no sidebar toggle. Buttons, switches, tables and sheets are drawn the way the design draws them instead of with the system's controls. Dragging still reorders libraries, apps and groups.
- b1b22dc: The menu bar widget never scrolls. When its libraries would not fit under the menu bar it folds them, then shows fewer, with the rest a click away in the dryfit window. It also keeps more room between the groups and the footer.
- 00ad2af: `dryfit add` builds an Nx library whose build target comes from a plugin. When `nx.json` lists the `@nx/js/typescript`, `@nx/vite`, `@nx/rollup` or `@nx/webpack` plugin and the library has that plugin's config file, it is built with `nx` under the target name the plugin is configured to use, instead of falling back to the npm script.
- c21f615: `dryfit add` builds an Nx library that has no `project.json` with Nx. When its `package.json` has a `build` script or `nx.targets.build`, or it has an `ng-package.json`, the library is built with `nx build` under the name Nx gives it, and its output folder is published, instead of falling back to `npm run build` and the library root.

## 0.8.1

### Patch Changes

- 9ed0aba: The menu bar app now follows the approved design more closely. Failed installs show their output on the library page with Copy output and Restore. Linked apps and an app's libraries are tables with column headers. The sidebar marks failures with a red dot and dev builds with a DEV chip. The failures window can open the library it is about, and the group editor has a filter.

## 0.8.0

### Minor Changes

- 001892e: A clearer menu bar app. The widget shows what needs attention first and lists at most three linked apps per library, with a search for linking more. The window keeps each page's header in place while the content scrolls, shows linked and available apps as rows with a status and a count, and has a filter in the sidebar. Sheets and the failures window use the same icons, colours and error messages.

## 0.7.0

### Minor Changes

- a070c64: Name apps the way `dryfit consumers` lists them. `link`, `restore`, `hide`, `unhide` and `group save` take an app's package name or folder name, such as `dryfit link shop` from the library's folder, as well as a path. A path that holds a known app still wins, and a name two apps share asks for a path.
- 6d5e700: Say when to restart a dev server. When an install clears an app's framework caches, `link`, `sync` and `watch` now print which app's dev server to restart; before, `sync` and `watch` hid that line entirely. After `link`, the next step no longer suggests the build still has to be installed.

### Patch Changes

- cb76d6e: Fixes from a full audit. Dev publishes no longer run the library's own `prepublishOnly`, `prepack` or `prepare` scripts, and `workspace:` devDependencies no longer block them. `NPM_TOKEN` and your own `NPM_CONFIG_*` settings now reach installs, and quoted npmrc tokens work. Watching a library that builds into its own folder, or holds an example app, no longer syncs in a loop. The same app reached through a symlink or with different letter case is one app, and dryfit refuses to snapshot files that already hold a dev build. Linking a pending or failed link again retries it. Workspace packages without their own lockfile are refused instead of changing the root lockfile. One unreadable folder no longer stops the search for apps.
  
  The commit guard leaves alone hooks that git tracks, symlinked hooks and hooks that are not shell scripts. It gives a hook back its original mode, stays while another linked app shares the hook, and a guard that cannot go in is reported as a warning instead of failing the link. `link --group` honours `--no-guard`, and `restore --group` refuses `--library`. `--build` refuses shell syntax, and `daemon status --json` prints JSON. The CLI no longer gives up on jobs longer than five minutes, and after a restart it no longer misses events. A second daemon cannot replace the running registry's password, and a bad npmrc registry no longer stops the daemon from starting. The login agent keeps proxy and CA settings.
  
  In the menu bar app, a slow start no longer shows a false timeout, an event it cannot read no longer drops the connection, refused requests no longer post notifications, and progress clears after the daemon restarts.
- f90e983: The menu bar app's Update button no longer fails with `ETARGET` right after a release: it asks npm to check
  the registry again instead of trusting its cached list of versions.

## 0.6.0

### Minor Changes

- ae17de7: The menu bar app gets a redesigned menu: each library is a card you can fold, with one-click links for the apps that use it, sync progress on the card, and Restore under the pointer. Settings moves into the dryfit window (the gear in the sidebar, or ⌘,), and the old ⋯ menu moves to a right-click on the menu bar icon. Drag libraries, apps and groups in the sidebar to order them; the menu follows. Installing dryfit from the app now says why it failed instead of offering the button again, and an app added by hand no longer shows up twice once linked.

### Patch Changes

- ae17de7: Linking a library that was never published now builds and publishes it, then installs it into the app,
  instead of recording a link that changed nothing; a failed build is reported and leaves the link pending.
  Finding apps no longer stops at a folder whose package.json uses none of your libraries (such as a stray
  `~/package.json`), and with no project folders configured the daemon searches the folders that hold your
  libraries.
- ae17de7: `dryfit link` with libraries that pin each other no longer fails on dev builds that pin a sibling's old dev
  build, such as those published by dryfit 0.4. It publishes them again before installing.
- 9ccffc6: The menu bar app's window now looks and works like a native macOS app: the sidebar is the system's source
  list (↑ and ↓ move through it, drag or ⌥⌘↑ and ⌥⌘↓ reorder it), page actions sit in the window's toolbar,
  buttons, switches and fields are the system's own, and menu items use title case.
- 0dc0597: The menu bar app is easier to use with the keyboard and easier to read. ↑ and ↓ move through the window's sidebar again, and rows move with ⌥⌘↑ and ⌥⌘↓ or **Move up** and **Move down** in their context menu; while you drag one, the marker shows where it will land. Grey captions are darker in light mode, so they meet WCAG AA contrast. Link, Restore and the window's other buttons show a spinner while their job runs, and the sidebar shows what dryfit is doing. The menu can restore an app after a failed install, and the right-click menu can start dryfit as well as stop it. **New group** won't overwrite a group with the same name. Settings now shows its errors instead of dropping them.

## 0.5.0

### Minor Changes

- ff4f9ec: Hide the apps you don't work on: `dryfit hide <app>` (or Hide App in the menu bar app) stops listing an app, even though it uses your libraries, and `dryfit unhide` (or Show in Settings) lists it again. Nothing in the app changes, and a linked app has to be restored first.
- 649ed40: Libraries from one workspace that pin each other exactly, such as an Nx workspace with independent releases, now work together. `dryfit link <app> --library a --library b` links several libraries in one step, each dev build pins the other registered libraries' dev builds, a sync also republishes the libraries that depend on the one that changed, and every install into an app puts all of its linked libraries in with one package manager run. Restoring one library also restores the linked libraries tied to it. A failed install names the libraries to link along.

### Patch Changes

- d5af514: `dryfit link` now exits 1 when the install into a consumer fails, with `--json` too, and `link --group`
  reports that member as failed instead of done. A failed link keeps the end of the package manager's
  output as `message`, so `link --json`, `status --json` and `dryfit status` show why (such as npm's
  `ERESOLVE`) without rerunning the install, and the daemon log records it.
- b30b0aa: In the menu bar app's window, a long sidebar no longer shows through the Add button at its bottom: the rows now stop at the bar's edge.

## 0.4.2

### Patch Changes

- 3db3667: `dryfit add --publish-dir` now keeps the detected build command, and `dryfit add --build` keeps the
  detected publish folder. Before, passing one flag left the library with no build step or publishing its
  sources.

## 0.4.1

### Patch Changes

- 0933325: Dev builds of a scoped library now always publish to dryfit's local registry. Before, an `@scope:registry` line in your `.npmrc`, or a `registry` in the library's `publishConfig`, sent them to that registry instead, often the public npm registry.

## 0.4.0

### Minor Changes

- 188ccb8: The menu bar app now notices when the dryfit it runs is older than the app, and offers to update it: one click runs `npm install --global @dryfit/cli@latest` and restarts dryfit on the new version, keeping your links and watches. When the app is the older side of a mismatch, it offers Check for Updates instead.

## 0.3.0

### Minor Changes

- a78632f: The menu bar app now keeps itself up to date: it checks for a new version once a day, downloads it in the background and installs it while you are not using it. Settings has a switch to be asked first, and the menu has Check for Updates…. Install the app from this release once more; later versions arrive on their own.

## 0.2.0

### Minor Changes

- 00e1d46: `dryfit agent install` teaches Claude Code to use dryfit: it installs a skill, shipped in the package, into `~/.claude/skills` (`--project` for this project's `.claude/skills`, `--dir` for another agent's skills folder), and `dryfit agent show` prints it. Under `--json`, errors now come as JSON on stderr too, `{ "error": { "code", "message", "hint" }, "exitCode" }`, so scripts and agents can tell what failed and what to do.

## 0.1.0

### Minor Changes

- 863f0e9: First release. dryfit publishes a library to a local registry and installs it into the projects that
  use it, with npm, pnpm, Yarn (2 and later) or Bun, and restores each project byte for byte afterwards.
  It comes with a daemon that rebuilds and reinstalls on every change, a CLI, a pre-commit guard that
  keeps dev builds out of commits, and a macOS menu bar app.
- 863f0e9: The daemon's API can preview a library folder before it is added (`inspect`) and read and change the project folders (`roots`, `setRoots`), so the menu bar app can set everything up without a terminal. The app has its own icon, lists the apps that use your libraries, and calls watching Auto-sync.
- 863f0e9: `dryfit restore --library <name>` (and `restore` in the daemon's API with `library`) puts one library in an app back on its release and keeps the app's other links. Restoring an app from a library's page in the menu bar app now does this, instead of restoring every library in that app.
