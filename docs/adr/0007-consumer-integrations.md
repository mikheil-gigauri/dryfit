# 0007. Consumer integrations for cache invalidation

**Status:** Accepted · 2026-11-18

## Context

After a successful install, dev servers often keep serving the old library. Angular's builder pre-bundles
dependencies into `.angular/cache`; Vite does the same in `node_modules/.vite`; Native Federation caches
shared bundles under `node_modules/.cache/native-federation`. This, more than linking itself, is why
"my change didn't apply" is so common.

## Decision

Framework knowledge lives in small integrations, each detected from the consumer's manifest and files:

```ts
interface ConsumerIntegration {
  readonly id: string; // 'angular', 'native-federation', 'vite', ...
  detect(project: ProjectInfo): boolean;
  cachePaths(project: ProjectInfo): string[];
}
```

After install, dryfit removes the union of cache paths for the detected integrations and notifies the
user (or a managed dev server, later) that a restart is needed. Users can add paths in config for anything
we do not detect.

The first integrations are Angular, Native Federation, Vite and Webpack/Module Federation, because they
cover the author's own stack and a large share of real use.

## Consequences

- Adding a framework is a single file with a fixture-based test, which makes it a good first contribution.
- Deleting caches costs one slower dev-server start per cycle, which is the price of never seeing stale code.

## Amendment · 2026-11-24 (live reload for Angular)

Clearing caches only helps the next start. The Angular CLI's dev server pre-bundles every dependency once,
when it starts, and its watcher skips `node_modules`, so a dev server that is already running keeps serving
the pre-bundled library after every install until it is restarted. Measured on a real Native Federation
app: an install, with the caches cleared, left the running dev server unchanged; the same install with the
library in `prebundle.exclude` was rebuilt and reloaded in the page within about a second, sync after
sync.

- **An integration may keep a live reload setting** in the consumer's config files while it is linked
  (`liveReload` on `ConsumerIntegration`). Angular's adds every linked library, and a `"dryfit:linked"`
  mark, to `prebundle.exclude` of each dev server target in `angular.json` or a root `project.json`, in its
  options and in configurations that set their own. A target with `prebundle: false` already rebuilds from
  `node_modules` and is left alone. Excluded libraries are built with the app, from files the dev server
  watches.
- **The edit changes only the setting.** The file is edited in place, keeping every other byte, its
  comments and its layout; one-line objects stay on one line.
- **The snapshot holds a copy of each such file** (`configs/` and `configFiles` in `meta.json`). Restore
  puts the copy back when the file is exactly what dryfit made of it, and otherwise takes out only the
  setting, keeping the user's own changes. A file that no longer parses stops the restore unless forced.
  A consumer linked before this amendment has no copy and gets no setting until it is linked again.
- **The commit guard refuses** a staged `angular.json` or `project.json` holding the mark.
- **No caches are cleared while the setting is on.** The first install after linking turns it on and
  clears caches as before, which asks for one restart; later installs find it on, clear nothing and ask for
  no restart, because the running dev server picks them up by itself.

Nx's own `@nx/angular:dev-server` executor and nested `project.json` files are not covered yet.
