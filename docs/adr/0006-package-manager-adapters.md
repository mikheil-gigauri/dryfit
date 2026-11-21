# 0006. Package manager adapters

**Status:** Accepted · 2026-11-18

## Context

The first users run npm, but an open-source tool that only supports npm loses most of its audience.
Package managers differ in exactly the operations dryfit needs: installing one package from another
registry, clean installs, lockfile formats, and how they record tarball URLs.

## Decision

The core depends on a `PackageManager` port; each manager is an adapter behind it:

```ts
interface PackageManagerAdapter {
  readonly name: 'npm' | 'pnpm' | 'yarn' | 'bun';
  readonly lockfile: string;
  install(spec: InstallSpec): Command; // one package, exact version, scoped registry
  cleanInstall(): Command; // npm ci, pnpm install --frozen-lockfile, ...
  findRegistryLeaks(lockfile: string, registryUrl: string): Leak[];
}
```

Adapters return command descriptions rather than running processes, so they are pure and unit-testable;
a `ProcessRunner` port executes them.

The registry is passed per invocation and per scope (`--@scope:registry=...` for npm and pnpm, environment
config for Yarn Berry), never written into the consumer's `.npmrc`.

Detection order for a consumer: the `packageManager` field in `package.json`, then the single lockfile
present, then npm. More than one lockfile is an error the user must resolve.

## Consequences

- npm ships first; pnpm, Yarn and Bun follow without touching the core.
- Every adapter runs the same contract test suite against a real registry (ADR 0009), so "supported" means
  tested.

## Amendment · 2026-11-19 (M5, all four adapters built)

Building pnpm, Yarn and Bun against real registries changed the port and two of the strategies above.

- **The port is split.** `PackageManagerAdapter` keeps `name`, `lockfiles`, `install` and `cleanInstall`,
  which return a `RunSpec`: a command plus optional environment variables for that command only.
  Publishing moved to a separate `Publisher` port, and it is always npm: Yarn cannot publish from a bare
  staging folder, and a library's own package manager does not matter once its output is staged. A
  manifest with `workspace:` or `catalog:` ranges is refused with a hint to publish the build output.
- **`findRegistryLeaks` is gone.** It was never called in production. The commit guard's pattern, a
  dev version ending in `dev.` and 14 digits, is the single check, and the contract suite runs it against
  each manager's real lockfile.
- **npm and pnpm install by version** with the scope pointed at dryfit for that command
  (`--@scope:registry` for npm, `--config.@scope:registry` for pnpm). pnpm 12 also needs
  `--config.minimumReleaseAge=0`, because its default one-day release-age gate refuses a minutes-old dev
  build. A plain `pnpm install` by the user while linked still applies the gate; the docs say so.
- **Yarn and Bun install from the tarball URL.** Neither lets a command override a scope's registry:
  Yarn reads `npmScopes` only from `.yarnrc.yml` (maps cannot be set by environment), and Bun ignores
  `--registry` for a scope mapped in `.npmrc` or `bunfig.toml`. Installing
  `name@<registry>/<name>/-/<base>-<version>.tgz` works whatever the project maps the scope to, and skips
  Yarn's release-age gate. The manifest holds the URL until restore. Yarn also gets
  `YARN_ENABLE_IMMUTABLE_INSTALLS=false` and the registry's host in `YARN_UNSAFE_HTTP_WHITELIST`.
- **Refused at detection:** Yarn 1 (from the `packageManager` field) and a project whose only lockfile is
  Bun's binary `bun.lockb`, with the command that converts it.
- **Restore removes lockfiles the snapshot did not have**, because Yarn writes one even for an install
  without a lockfile.

The contract suite now installs with the scope pointed at a dead registry, so an adapter that ignores
dryfit's registry fails, and checks that nothing in the project changes but the manifest and lockfile.
An end-to-end test links one library into an npm, a pnpm, a Yarn and a Bun app at once.

## Amendment · 2026-11-22 (incremental restore)

`cleanInstall` takes `incremental`. Restore sets it when the consumer has a `node_modules`, and npm then runs
`npm install` instead of `npm ci`: it follows the restored lockfile too, but changes only what differs from
it (a dev build or two) where `npm ci` deletes `node_modules` and installs everything. On a sample app of 217
top-level packages that took 0.35 s against 1.5 s, and the gap grows with the app; in an Nx workspace `npm ci`
reinstalls the whole workspace. pnpm, Yarn and Bun already install incrementally and ignore the option.

- **When the incremental install fails**, restore runs the full clean install, so the result is the one it
  always was.
- **A lockfile that the install rewrote goes back to the snapshot's bytes**, which keeps the restore exact
  whichever install ran.
- **Without a `node_modules`**, or without a lockfile, nothing changes.

The contract suite checks the incremental restore against every real package manager.
