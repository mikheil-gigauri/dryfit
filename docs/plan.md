# Build plan

Each milestone ends in something usable and is done only when its exit check passes. Design decisions are
in [`docs/adr`](adr/README.md).

## M0 · Foundations

Workspace, TypeScript, Vitest, Biome, ADRs, first TDD slice of the core: dev version scheme (ADR 0004) and
package manager detection (ADR 0006).

**Exit:** `npm test`, `npm run typecheck` and `npm run lint` pass from a clean clone.

## M1 · Core pipeline, in-process

The use cases with fake ports: register library, discover consumers, link (with snapshot), publish, install,
invalidate caches, restore. npm adapter. Angular, Native Federation and Vite integrations.

**Exit:** unit tests cover every use case, including restore after a failed install.

**Status:** done. Use cases live in `core/use-cases`, the npm adapter in `adapters/package-managers`, the
integrations in `adapters/integrations`. Tests run against an in-memory file system that shares a contract
suite with the real adapter (M2) and a simulated npm that really rewrites manifests and lockfiles, so the
restore tests prove byte-for-byte equality rather than "the right commands ran". Key behaviours were
mutation-checked: removing them makes tests fail.

Deferred on purpose: link groups and the version-coherence warning (M3, they are client features over
existing state), the commit guard hook (M3), peer-range overrides (M2, needs a real registry to verify).
Paths in core are POSIX; Windows support is not planned before M5.

## M2 · Real registry and the npm contract

Embedded Verdaccio behind the `Registry` port. npm adapter contract suite against it. Peer-range overrides
(ADR 0004).

**Exit:** the e2e test links a fixture library into two fixture consumers, sees the new code, restores, and
both consumers are byte-identical to before.

**Status:** done. `src/e2e/link-cycle.integration.test.ts` runs the exit check with nothing faked: a public
registry holding the release, dryfit's registry proxying it, real npm, two consumers (one without a
lockfile), two edit cycles, and a byte-for-byte restore. Mutating restore makes it fail.

- Real adapters: `NodeFileSystem` (passes the shared contract), `NodeProcessRunner` (no shell, strips
  inherited `npm_*` config), `JsonStateStore` (atomic, versioned), `VerdaccioRegistry`.
- The registry refuses browser requests (`Origin` header or a foreign `Host`), because Verdaccio's
  permissive CORS would otherwise let any web page read private dev builds. Publishing uses Basic auth for
  one user seeded before the port opens, with registration disabled and a password that changes on every
  start; it reaches npm through a private staged `.npmrc`, never the process list. Storage is `0700`.
  Details in the ADR 0002 amendment.
- Peer-range overrides were not needed: real npm installs a dev prerelease against a peer range. ADR 0004
  is amended, and a contract test pins the behaviour for future adapters.
- Tests are split: `npm test` (unit, about a second) and `npm run test:integration` (real registries).
- A review after the exit check led to: the auth redesign above; `copyDir` and the in-memory fake now
  agree on empty folders and a missing source (new contract cases); state entries are validated on load
  and the state file is flushed before its atomic rename; integration tests ignore the machine's global
  npmrc; the e2e compares the installed dependency tree, not only manifests and lockfiles.
- Deferred to M3, where the daemon's process lifecycle is designed: timeouts and cancellation for child
  processes (a hung `npm install` currently waits forever), and whether Verdaccio leaves timers or handles
  behind after `stop()` (harmless in a one-shot test run, relevant to a long-lived daemon that restarts
  its registry). Also open: how `npm publish` treats symlinks inside `publishDir`; staging copies them
  verbatim and npm decides.
- Verdaccio is pinned to 6.x because 7 requires Node 24. `npm audit --omit=dev` reports two root
  advisories inside Verdaccio's tree (ReDoS in `picomatch` and `minimatch`); both need attacker-controlled
  glob patterns, which dryfit's fixed config and loopback-only registry do not expose. Revisit when the
  Node 22 floor is raised (Node 22 leaves maintenance in April 2027) or if an advisory becomes reachable.

## M3 · Daemon and CLI

`dryfitd` with the HTTP API, token auth and SSE. CLI commands: `init`, `add`, `link`, `unlink`/`restore`,
`watch`, `status`, `doctor`, `daemon start|stop|status`, `hook install`. launchd agent.

**Exit:** the author uses dryfit on `shared-fe-library` and its MFEs for a full working week.

**Status:** built; the exit check is the author's working week, which has not happened yet. Decisions are in
ADR 0012. `src/e2e/cli-cycle.integration.test.ts` rehearses that week in about fifteen seconds through the
`dryfit` binary alone: init, add, discover, save and link a group, sync, a real `git commit` refused by
the guard, watch picking up a saved file, and a byte-for-byte group restore with the guard removed.

- Daemon (`src/daemon`): the API contract with a small validator that can describe itself as JSON
  Schema for M4, a serial job queue where syncs coalesce, an event hub with `Last-Event-ID` replay, the
  HTTP server (token, browser refusal, error mapping, SSE), and `startDaemon`, which proxies the user's
  npm registries with their credentials held in memory.
- CLI (`src/cli`): every command above plus `consumers`, `sync`, `unwatch`, `events`, `group` and
  `remove`, all with `--json`. It starts the daemon on demand, restarts it on version skew, and is bundled
  by tsdown into one 130 kB file.
- Core additions: groups and the coherence warning, unregistering, library build detection (Nx, Angular
  CLI, npm script), the commit guard's hook text, and state version 2 (version 1 files are upgraded).
- `hook install` became part of `link`: the guard is installed by default and kept current on every sync,
  because Husky regenerates hook files on install (ADR 0012).
- From M2's deferred list: child processes now have a timeout and are cancelled on shutdown, killing the
  whole process tree. The Verdaccio shutdown question is settled by design: `daemon run` exits the process
  once stopped, so lingering timers cannot keep it alive. Symlinks in `publishDir` remain open.
- A review of the M3 diff (two reviewers, every finding checked against the code) led to fixes, each
  with a test that failed first:
  - Security:
    - a damaged token file could make the daemon accept `Bearer undefined`; the token is now linked
      into place whole, and a damaged one is replaced;
    - `daemon stop` could signal a reused pid named by a stale `daemon.json`; health is now public, and
      the CLI acts only on the pid that health confirms;
    - a losing second registry start rewrote the running registry's htpasswd; it is now written only
      once the port is claimed.
  - Commit guard: it missed non-ASCII paths, deleted a hook that had been empty before, and could cut
    off user lines when its end marker was edited away.
  - Robustness:
    - a command that leaves a background process holding its output no longer hangs until the
      15-minute timeout;
    - an SSE client that stops reading is cut off instead of buffered for;
    - watch failures are reported and turn watching off;
    - a failed daemon start releases both ports;
    - `stop` always resolves.
  - CLI:
    - `--json` exits 1 when something failed;
    - `restore` works from a subfolder and keeps going past one failing consumer;
    - `add` without flags keeps the stored build;
    - `doctor` checks that the launchd agent is loaded;
    - an Angular library without `dest` publishes ng-packagr's `dist`.
- Known limits:
  - On Linux, Node's recursive `fs.watch` also watches `node_modules` before dryfit filters it, which
    can exhaust inotify on large repositories; Linux is an M5 platform, so a filtered walk lands then.
  - Nx projects defined without `project.json`, or with inferred targets, fall back to an npm build
    script or to publishing the library root; `add --build/--publish-dir` covers them.
- Not covered by automated tests: restarting a daemon of another version (it needs two builds), and
  `daemon install`, whose plist is unit-tested but which was not loaded into launchd on the author's
  machine without asking.

## M4 · Menu bar app

SwiftUI `MenuBarExtra` client: library and consumer status, link and restore, watch toggle, groups,
notifications on failure.

**Exit:** a full cycle can be driven from the menu bar alone; view-model tests and light/dark snapshots
pass.

**Status:** built; the exit check's last part, clicking through the cycle by hand, has not happened yet.
Decisions are in ADR 0013. `apps/menubar` is a Swift package (`DryfitAPI`, `DryfitMenu`, the `Dryfit`
app), tested with Swift Testing: 45 tests, five of them light/dark snapshot pairs. `npm run menubar:e2e` drives
the menu's model, which every control calls, through a full cycle against a real daemon in a throwaway
sandbox in about three seconds: start dryfit from the menu, discover, link, sync, watch, an edit reaching
the consumer, restore.

- The API contract is generated: `npm run api:export` writes `packages/dryfit/api/schema.json` and
  `fixtures.json` from the TypeScript types. The TypeScript test fails when they are stale, and the Swift
  tests decode every fixture and check operations, error codes and event types against the schema.
- The app finds the daemon through `daemon.json`, trusts it only when health confirms the pid, refuses
  another API version, and starts it only when asked: the launchd agent if installed, otherwise
  `dryfit daemon start` in a login shell, then an interactive one for nvm users.
- It follows the daemon from launch and resumes the event stream after the last event id, so failures
  are noticed with the menu closed. Builds, installs, publishes and watches that fail become
  notifications in `Dryfit.app`, and a click opens the failure window with the full output.
- `apps/menubar/scripts/bundle.sh` builds `Dryfit.app` (menu bar only, signed ad hoc). It installs
  nothing; Open at Login registers the app only when turned on.
- Known limits:
  - Snapshots are rendered by AppKit on the author's macOS 27; another macOS version may draw controls
    differently, and the references then need recording again (`SNAPSHOT_RECORD=1`).
  - The menu bar extra was not clicked through by an automated tool, which could not see an
    `LSUIElement` app; the end-to-end test covers everything below the buttons.

## M5 · Open-source launch

pnpm, Yarn and Bun adapters passing the contract suite. Website with landing page and docs (ADR 0011).
GitHub Actions for tests on macOS and Linux, Changesets releases with npm provenance. README, contributing
guide, issue templates. Signed and notarized menu bar build, Homebrew cask.

**Exit:** `npx @dryfit/cli init` works for someone who has never seen the project.

**Status:** built; the exit check is rehearsed but the package is not on npm yet, and nothing has run on
GitHub, because the repository is not published. `scripts/newcomer.sh` packs the CLI and runs it the way a
newcomer would, with `npx` in an empty home folder: init, add, consumers, link, an edit reaching the app,
a refused commit, and a byte-for-byte restore. It passes locally and runs in CI.

- Package managers: pnpm, Yarn 2+ and Bun adapters pass the same contract suite as npm against real
  registries, and an end-to-end test links one library into all four at once. pnpm installs by version;
  Yarn and Bun install from the tarball URL, because neither lets a command override a scope's registry.
  Publishing is always npm. Yarn 1 and binary-only `bun.lockb` projects are refused with a fix. The ADR 0006
  amendment has the details.
- Linux: a `walk` watcher strategy, one watch per relevant folder, replaces recursive `fs.watch` there
  (ADR 0012 amendment). It runs the same tests as the macOS strategy, but has not run on real inotify yet.
- Website in `apps/site` (ADR 0011 amendment): a landing page with a working diagram of the cycle,
  guides, a CLI reference generated from the CLI's help text, the ADRs, and the menu's real snapshots.
  Deployed to GitHub Pages by `site.yml`.
- CI (`ci.yml`): typecheck, lint, build, unit and integration tests, and the newcomer check on Ubuntu with
  Node 22.12 and 24 and on macOS; the menu bar app's tests and a universal bundle on macOS.
- Releases (`release.yml`): Changesets with npm provenance; then, when Apple secrets are present, a signed,
  notarized universal `Dryfit.app` attached to the GitHub release and a cask pushed to
  `mikheil-gigauri/homebrew-dryfit`. CONTRIBUTING lists the secrets.
- The `npx` hint: `init` run through `npx` suggests `npx @dryfit/cli` commands and how to install globally.
- Known limits:
  - Signing, notarization and the cask are scripted but untested: they need an Apple Developer ID.
  - With pnpm's release-age gate, a plain `pnpm install` by the user while linked refuses the dev build;
    `dryfit sync` or a restore is the way through, and the docs say so.
  - Snapshot tests compare only on the macOS major they were recorded on; elsewhere, such as CI's
    runners, they are skipped with a note.
- To launch: create the GitHub repository, enable Pages from Actions, merge the first "Version packages"
  pull request, publish that first version by hand (npm only lets a package that exists trust a
  workflow), then set up npm trusted publishing for `release.yml`; later releases need no token.

## Later

`--fast` mode (copy `dist` between full installs), managed dev-server restarts, editor extension,
Webpack/Module Federation and Next.js integrations.
