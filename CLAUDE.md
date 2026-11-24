# dryfit — agent guide

dryfit tests unreleased npm libraries inside real consumer apps: a daemon with a private Verdaccio publishes every
library change as a dev version, installs it into the apps you link, clears their caches, and restores them exactly.
A CLI (`@dryfit/cli`, TypeScript, Node 22.12+) and a macOS menu bar app (SwiftUI, macOS 26+) are thin clients of the
daemon. What it does for users: README.md. Where things live and how to release: CONTRIBUTING.md (read only the
section you need).

## Build & test

- `npm install`, then `npm test` (unit, seconds), `npm run test:integration` (real Verdaccio, npm, pnpm, Yarn, Bun and
  git; about a minute), `npm run typecheck`, `npm run lint` (Biome; `npm run format` fixes it).
- Menu bar app (`apps/menubar`, a SwiftPM package, no Xcode project): `npm run menubar:test`
  (`cd apps/menubar && xcrun swift test`, always `xcrun swift`), one suite with `-- --filter <Suite>`;
  `npm run menubar:e2e` drives it against a real daemon; `npm run menubar:bundle` builds `Dryfit.app`.
- `scripts/newcomer.sh` packs the CLI and runs it the way a first-time user would. Set `DRYFIT_PORTS=api,registry` when
  dryfit already runs on this Mac.
- Before handoff: the narrowest check while iterating, then `npm test`, `npm run typecheck`, `npm run lint`, and
  `npm run menubar:test` when the app changed.

## Code map

| Where                                   | Look here for                                                                                                        |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `packages/dryfit/src/core`              | the logic, no Node APIs, tested against in-memory fakes                                                              |
| `packages/dryfit/src/adapters`          | Node, Verdaccio, git, package managers; a new one passes `describePackageManagerContract`                            |
| `packages/dryfit/src/daemon`, `src/cli` | the background service and its HTTP + SSE API, the CLI (`USAGE` in `cli/main.ts` generates the site's CLI reference) |
| `packages/dryfit/api/`                  | `schema.json` + `fixtures.json`, the contract the Swift app decodes (`npm run api:export -w @dryfit/cli`, ADR 0013)  |
| `apps/menubar/Sources/DryfitAPI`        | the app's API client and daemon launcher; no SwiftUI                                                                 |
| `apps/menubar/Sources/DryfitMenu`       | `MenuModel` (the view model) and `UI/` (the views and their kit)                                                     |
| `apps/site`                             | Astro + Starlight docs; guides in `src/content/docs/guides`                                                          |
| `apps/promo`                            | the promo video (Remotion), its own lockfile: `npm ci --prefix apps/promo`                                           |
| `docs/adr`                              | one record per decision; a changed decision gets an amendment or a new record                                        |
| `docs/design`                           | the approved mockups: the spec for the menu bar app's UI                                                             |

## The menu bar app's UI

The mock is the spec: `docs/design/dryfit-states.html` has every state (`<section id="m-ok">` for the widget, `w-…`
the window, `s-…` sheets, `d-…` dialogs, `f-…` the failures window) in light and dark. It is ~260 KB: `grep -n` for a
state's id and read that section only.

- Colours and radii live in `apps/menubar/tokens.json`. Change a value there, then `npm run menubar:tokens`, which
  writes `UI/Tokens.swift` and the `tokens:begin` block of every mock. Never edit either by hand; CI fails when
  they're stale. Type sizes and line heights are in `UI/Theme.swift`.
- Build from the kit in `UI/Controls.swift`, `UI/Layout.swift` and `UI/Icons.swift`; each view names the mock's CSS
  class it copies (`.btn`, `.sw`, `.chip`). A missing control becomes a kit view, not one-off styling in a page.
- A layout or style change edits the mock first, then the code; a copy-only change edits the code only.
- Prove it: `npm run menubar:compare -- <state …>` renders the mock's states and the app's scenes of the same name
  (`LiveScenes` in `Tests/DryfitMenuTests/LiveCapture.swift`, drawn offscreen by `Snapshots.swift`), and writes
  mock | app | diff to `apps/menubar/.build/compare/diff/`, printing the share that differs and any size mismatch.
  Open the diff of every state you touched, light and dark. Done means only text antialiasing and data the app
  computes differently are left; list anything else in the PR as a deviation. A new state gets a `LiveScenes` scene
  with the mock's id and the mock's data.
- `DRYFIT_LIVE=<dir> npm run menubar:test -- --filter LiveCapture` photographs real windows (site screenshots, the
  promo); it needs Screen Recording and a screen, so it's not a check.

## Rules

- Test first: a behaviour change starts with a failing test, a bug fix with a test that reproduces it (ADR 0009).
  The restore guarantee is an executable test; never weaken one to make a change pass.
- `DryfitAPI` never imports SwiftUI. A daemon API change updates `packages/dryfit/api/` and the Swift decoder together.
- User-facing copy: plain English, short sentences, say what happened and what to do next; name apps and libraries
  as `dryfit consumers` lists them.
- Smallest diff that does the job; no drive-by refactors, renames or formatting. Match the surrounding code and its
  comment density.

## Branches, commits, releases

- Branch from `main`, open pull requests into `main`, and fill in the PR template. `main` needs an approving review;
  ask before merging with an admin override, every time.
- Commits use conventional prefixes, a short lower-case sentence (`fix(menubar): …`, `feat(cli): …`, `docs: …`);
  see `git log`.
- A pull request that changes what users get adds a changeset (`npx changeset`, `@dryfit/cli`, patch for fixes,
  minor for features while 0.x). Tests, docs and CI need none.
- Releases happen by merging the "Release" pull request that `release.yml` keeps open; never publish by hand.

## History

`docs/adr/` and git log are the history, not any conversation: decisions go in an ADR.
