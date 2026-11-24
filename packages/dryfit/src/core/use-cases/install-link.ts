import { DryfitError } from '../errors.ts';
import type { DryfitState, LibraryRecord, LinkRecord, Manifest, SnapshotMeta } from '../model.ts';
import type { CoreDeps, InstallPackage, ProjectInfo } from '../ports.ts';
import { cachePathsFor } from '../project/cache-paths.ts';
import { connectedTo, loadLibraryGraph, runtimeDependencies } from '../project/library-graph.ts';
import { liveReloadFiles } from '../project/live-reload.ts';
import { loadProject } from '../project/load-project.ts';
import { findDependency } from '../project/manifest.ts';
import { findWorkspacePackages, workspaceRootOf } from '../project/workspace-packages.ts';
import { tryParseJson } from '../util/json.ts';
import { joinPath } from '../util/path.ts';
import {
  adapterFor,
  commandOutput,
  failureMessage,
  runSafely,
  sameLink,
  snapshotDir,
  withLink,
} from './shared.ts';

/** One library's dev build, as installed into a consumer. */
export interface LibraryVersion {
  readonly library: string;
  readonly version: string;
}

export type InstallOutcome =
  | {
      readonly consumer: string;
      readonly ok: true;
      /** The version of the first library in `libraries`, the one the install was for. */
      readonly version: string;
      /** Every dev build installed in the same run (ADR 0014). */
      readonly libraries: readonly LibraryVersion[];
      readonly clearedCaches: readonly string[];
    }
  | {
      readonly consumer: string;
      readonly ok: false;
      readonly version: string;
      readonly libraries: readonly LibraryVersion[];
      readonly output: string;
    };

export interface InstallLinksInput {
  readonly consumer: string;
  /** Libraries linked into the consumer and the dev versions to install, the main one first. */
  readonly libraries: readonly { readonly library: LibraryRecord; readonly version: string }[];
}

/**
 * Installs dev versions of several libraries linked into one consumer in a single package manager run,
 * then keeps the dev server's live reload setting on, or clears the caches that would hide them
 * (ADR 0007). One run lets dev builds that pin each other
 * exactly resolve together (ADR 0014).
 *
 * Every expected failure is an outcome, not an exception: a library the consumer no longer depends on
 * is marked `failed` and left out, and a package manager that is unsupported or fails marks every
 * library in the run `failed`. The snapshot still allows a restore.
 */
export async function installLinks(
  deps: CoreDeps,
  { consumer, libraries }: InstallLinksInput,
): Promise<{ readonly outcome: InstallOutcome; readonly links: readonly LinkRecord[] }> {
  const versions = libraries.map(({ library, version }) => ({ library: library.name, version }));
  const [main] = versions;
  if (main === undefined) throw new DryfitError('invalid-request', `Nothing to install into ${consumer}`, {});

  const failures = new Map<string, string>();
  const fail = async (output: string, failing: readonly LibraryVersion[] = versions) => {
    for (const { library, version } of failing) {
      failures.set(library, output);
      deps.events.emit({ type: 'install:failed', library, consumer, version, output });
    }
    const links = await saveLinks(deps, consumer, versions, failures);
    return {
      outcome: { consumer, ok: false as const, version: main.version, libraries: versions, output },
      links,
    };
  };

  let project: Awaited<ReturnType<typeof loadProject>>;
  let adapter: ReturnType<typeof adapterFor>;
  try {
    project = await loadProject(deps.fs, consumer, deps.integrations);
    adapter = adapterFor(deps, project);
  } catch (error) {
    if (error instanceof DryfitError) return fail(error.message);
    throw error;
  }

  const packages: InstallPackage[] = [];
  const gone: LibraryVersion[] = [];
  for (const entry of versions) {
    const declaration = findDependency(project.manifest, entry.library);
    if (declaration)
      packages.push({ name: entry.library, version: entry.version, dependencyField: declaration.field });
    else gone.push(entry);
  }
  for (const entry of gone) {
    const output = `${consumer} no longer depends on ${entry.library}`;
    failures.set(entry.library, output);
    deps.events.emit({ type: 'install:failed', ...entry, consumer, output });
  }
  const installing = versions.filter((entry) => !failures.has(entry.library));
  if (installing.length === 0) return fail([...failures.values()].join('\n'), []);

  for (const entry of installing) deps.events.emit({ type: 'install:started', ...entry, consumer });
  const result = await runSafely(
    deps,
    adapter.install({ cwd: consumer, packages, registryUrl: deps.registryUrl }),
  );
  if (result.exitCode !== 0) {
    const hints = [
      await unlinkedSiblingsHint(deps, project.manifest, consumer, installing),
      await unregisteredSiblingsHint(deps, project.manifest, consumer, installing),
    ];
    return fail([commandOutput(result), ...hints].filter(Boolean).join('\n\n'), installing);
  }

  // A dev server whose live reload setting was already on picks the install up by itself; clearing its
  // caches would only make it ask for a restart (ADR 0007).
  const linked = (await deps.state.load()).links.filter((link) => link.consumer === consumer);
  const names = [
    ...new Set([...linked.map((link) => link.library), ...installing.map((entry) => entry.library)]),
  ];
  const live = await keepLiveReload(deps, project, names);
  const clearedCaches = live ? [] : cachePathsFor(project, deps.integrations);
  for (const path of clearedCaches) await deps.fs.remove(joinPath(consumer, path));

  for (const entry of installing) deps.events.emit({ type: 'install:succeeded', ...entry, consumer });
  if (clearedCaches.length > 0) deps.events.emit({ type: 'caches:cleared', consumer, paths: clearedCaches });

  const links = await saveLinks(deps, consumer, versions, failures);
  if (failures.size > 0) {
    const output = [...failures.values()].join('\n');
    return { outcome: { consumer, ok: false, version: main.version, libraries: versions, output }, links };
  }
  return {
    outcome: { consumer, ok: true, version: main.version, libraries: versions, clearedCaches },
    links,
  };
}

/**
 * Turns on, or keeps on, the live reload setting of each config file the consumer's snapshot holds a
 * copy of; a file without one could not be put back on restore, so it is left alone. True when the
 * setting was already on in every such file, so a running dev server picks the install up by itself.
 */
async function keepLiveReload(
  deps: CoreDeps,
  project: ProjectInfo,
  libraries: readonly string[],
): Promise<boolean> {
  const metaText = await deps.fs.readText(joinPath(snapshotDir(deps, project.root), 'meta.json'));
  const meta =
    metaText === undefined ? undefined : (tryParseJson(metaText) as Partial<SnapshotMeta> | undefined);
  const settings = liveReloadFiles(project, deps.integrations).filter(({ file }) =>
    meta?.configFiles?.includes(file),
  );
  if (settings.length === 0) return false;

  let alreadyOn = true;
  for (const { file, setting } of settings) {
    const path = joinPath(project.root, file);
    const text = await deps.fs.readText(path);
    const edited = text === undefined ? undefined : setting.apply(text, libraries);
    if (edited !== undefined) await deps.fs.writeText(path, edited);
    if (text === undefined || edited !== undefined || !setting.isOn(text, libraries)) alreadyOn = false;
  }
  return alreadyOn;
}

/**
 * The dev builds to install when a consumer's set is installed again: every linked library that has
 * been published, at its latest dev version, with `first` (if linked) leading.
 */
export function linkedSet(
  state: DryfitState,
  consumer: string,
  first?: string,
): { library: LibraryRecord; version: string }[] {
  const set = state.links.flatMap((link) => {
    if (link.consumer !== consumer) return [];
    const library = state.libraries.find((candidate) => candidate.name === link.library);
    const version = library?.lastPublishedVersion;
    return library && version !== undefined ? [{ library, version }] : [];
  });
  return [
    ...set.filter((entry) => entry.library.name === first),
    ...set.filter((entry) => entry.library.name !== first),
  ];
}

/**
 * When an install fails, registered libraries tied to the installed ones that the consumer uses but has
 * not linked are the usual cause: their releases pin the old versions, or the dev builds pin theirs.
 */
async function unlinkedSiblingsHint(
  deps: CoreDeps,
  manifest: Manifest,
  consumer: string,
  installing: readonly LibraryVersion[],
): Promise<string | undefined> {
  const state = await deps.state.load();
  const graph = await loadLibraryGraph(deps.fs, state.libraries);
  const linked = new Set(
    state.links.filter((link) => link.consumer === consumer).map((link) => link.library),
  );
  const names = installing.map((entry) => entry.library);
  const tied = new Set(names.flatMap((name) => [...connectedTo(graph, name)]));
  const missing = [...tied].filter((name) => !linked.has(name) && findDependency(manifest, name)).sort();
  if (missing.length === 0) return undefined;
  const all = [...new Set([...linked, ...missing])].map((name) => `--library ${name}`).join(' ');
  return `${consumer} also uses ${missing.join(', ')}, tied to ${names.join(', ')} by their workspace's dependencies but not linked. Libraries that pin each other must be installed together: dryfit link ${consumer} ${all}`;
}

/**
 * When an install fails, a package the dev builds depend on that lives in the same workspace as their
 * library, and that the consumer uses but dryfit does not know, is the usual cause: the dev build pins
 * the workspace's version of it, the consumer's release another one (ADR 0014).
 */
async function unregisteredSiblingsHint(
  deps: CoreDeps,
  manifest: Manifest,
  consumer: string,
  installing: readonly LibraryVersion[],
): Promise<string | undefined> {
  const state = await deps.state.load();
  const registered = new Set(state.libraries.map((library) => library.name));
  const names = installing.map((entry) => entry.library);
  const found = new Map<string, { readonly folder: string; readonly dependents: string[] }>();
  for (const library of state.libraries.filter((candidate) => names.includes(candidate.name))) {
    const wanted = new Set(
      [...(await runtimeDependencies(deps.fs, library))].filter(
        (name) => !registered.has(name) && findDependency(manifest, name),
      ),
    );
    if (wanted.size === 0) continue;
    const root = await workspaceRootOf(deps.fs, library.root);
    if (root === undefined) continue;
    for (const [name, folder] of await findWorkspacePackages(deps.fs, root, wanted)) {
      const sibling = found.get(name) ?? { folder, dependents: [] };
      sibling.dependents.push(library.name);
      found.set(name, sibling);
    }
  }
  if (found.size === 0) return undefined;

  const siblings = [...found.keys()].sort();
  const linked = state.links.filter((link) => link.consumer === consumer).map((link) => link.library);
  const all = [...new Set([...names, ...linked, ...siblings])].map((name) => `--library ${name}`).join(' ');
  const adds = siblings.map((name) => `dryfit add ${found.get(name)?.folder}`);
  const reasons = siblings.map((name) => {
    const dependents = found.get(name)?.dependents ?? [];
    return `${dependents.join(', ')} ${dependents.length === 1 ? 'depends' : 'depend'} on ${name}, which ${consumer} also uses, but dryfit does not know ${name}.`;
  });
  return `${reasons.join(' ')} Libraries that pin each other must be installed together. Register ${siblings.length === 1 ? 'it' : 'them'} from the workspace, then link them together: ${[...adds, `dryfit link ${consumer} ${all}`].join(' && ')}`;
}

/**
 * Writes the links against freshly loaded state, so concurrent edits to other records survive. Keeps
 * what this function does not own (such as the guard flag); a failure keeps the last good version and
 * records why, and a success clears the last failure's message.
 */
async function saveLinks(
  deps: CoreDeps,
  consumer: string,
  versions: readonly LibraryVersion[],
  failures: ReadonlyMap<string, string>,
): Promise<LinkRecord[]> {
  let state = await deps.state.load();
  const saved: LinkRecord[] = [];
  for (const { library, version } of versions) {
    const previous = state.links.find((candidate) => sameLink(candidate, { library, consumer }));
    const failure = failures.get(library);
    const link: LinkRecord =
      failure === undefined
        ? {
            ...previous,
            library,
            consumer,
            status: 'installed',
            installedVersion: version,
            message: undefined,
          }
        : {
            ...previous,
            library,
            consumer,
            status: 'failed',
            installedVersion: previous?.installedVersion,
            message: failureMessage(failure),
          };
    state = withLink(state, link);
    saved.push(link);
  }
  await deps.state.save(state);
  return saved;
}
