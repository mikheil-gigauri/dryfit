import { DryfitError } from '../errors.ts';
import { DEV_VERSION_PATTERN } from '../guard/commit-guard.ts';
import type { DryfitState, LibraryRecord, LinkRecord, SnapshotMeta } from '../model.ts';
import type { CoreDeps, PackageManagerAdapter, ProjectInfo } from '../ports.ts';
import { dependencyOrder, loadLibraryGraph } from '../project/library-graph.ts';
import { liveReloadFiles } from '../project/live-reload.ts';
import { enclosingWorkspace, loadProject } from '../project/load-project.ts';
import { findDependency } from '../project/manifest.ts';
import { joinPath } from '../util/path.ts';
import { installLinks, linkedSet } from './install-link.ts';
import { publishLibrary } from './publish-library.ts';
import { adapterFor, requireLibrary, sameLink, snapshotDir, withLink } from './shared.ts';
import { publishSet, staleBuilds } from './sync-library.ts';

export interface LinkConsumerInput {
  readonly library: string;
  readonly consumer: string;
}

export interface LinkLibrariesInput {
  readonly libraries: readonly string[];
  readonly consumer: string;
}

/** Links one library into a consumer; see `linkLibraries`. */
export async function linkConsumer(deps: CoreDeps, input: LinkConsumerInput): Promise<LinkRecord> {
  const [link] = await linkLibraries(deps, { libraries: [input.library], consumer: input.consumer });
  if (!link) throw new DryfitError('invalid-request', `Linking ${input.library} returned nothing`, {});
  return link;
}

/**
 * Opts a consumer in to receiving dev versions of libraries (ADR 0005). The consumer's manifest and
 * lockfiles are snapshotted before anything changes. Newly linked libraries that were never published
 * are built and published first, so a link always changes the app; then the consumer's whole linked
 * set is installed in one run, so libraries that pin each other go in together (ADR 0014). Dev builds
 * in the set that pin a sibling's old dev build are published again before that. Every library is
 * checked before anything is touched.
 */
export async function linkLibraries(deps: CoreDeps, input: LinkLibrariesInput): Promise<LinkRecord[]> {
  // One spelling per folder, so `/repos/shop/` and `/repos/shop` share one link and one snapshot.
  const consumer = joinPath(input.consumer);
  const state = await deps.state.load();
  const libraries = [...new Set(input.libraries)].map((name) => requireLibrary(state, name));
  if (libraries.length === 0) throw new DryfitError('invalid-request', 'Which libraries to link?', {});

  const project = await loadProject(deps.fs, consumer);
  for (const library of libraries) {
    if (!findDependency(project.manifest, library.name)) {
      throw new DryfitError('not-a-consumer', `${consumer} does not depend on ${library.name}`, {
        consumer,
        library: library.name,
      });
    }
  }
  const adapter = adapterFor(deps, project);

  const existing = (name: string) => state.links.find((link) => sameLink(link, { library: name, consumer }));
  const added = libraries.filter((library) => !existing(library.name));
  // A link left pending by a failed build, or failed by a failed install, is tried again: linking it
  // once more is how the user retries after fixing the cause.
  const retried = libraries.filter((library) => {
    const link = existing(library.name);
    return link !== undefined && link.status !== 'installed';
  });
  const toInstall = [...added, ...retried];

  if (toInstall.length > 0) {
    let latest = state;
    if (added.length > 0) {
      const consumerAlreadyLinked = state.links.some((link) => link.consumer === consumer);
      if (!consumerAlreadyLinked) {
        await refuseWorkspaceMember(deps, project, adapter);
        await takeSnapshot(deps, project, adapter);
      }

      // Reload: the snapshot took file I/O, and another command may have saved state meanwhile.
      latest = await deps.state.load();
      for (const library of added)
        latest = withLink(latest, { library: library.name, consumer, status: 'pending' });
      await deps.state.save(latest);
    }

    // A build or publish failure throws here and leaves the links pending: nothing was installed.
    latest = await publishFirstBuilds(deps, latest, toInstall);
    latest = await republishStaleBuilds(deps, latest, consumer);
    await installLinks(deps, { consumer, libraries: linkedSet(latest, consumer, toInstall[0]?.name) });
  }

  const { links } = await deps.state.load();
  return libraries.flatMap(
    (library) => links.find((link) => sameLink(link, { library: library.name, consumer })) ?? [],
  );
}

/**
 * Publishes the libraries among `added` that have no dev build yet, each after the ones it depends on
 * so its build pins theirs. Returns the state to install from.
 */
async function publishFirstBuilds(
  deps: CoreDeps,
  state: DryfitState,
  added: readonly LibraryRecord[],
): Promise<DryfitState> {
  const unpublished = added.filter((library) => library.lastPublishedVersion === undefined);
  if (unpublished.length === 0) return state;
  const graph = await loadLibraryGraph(deps.fs, state.libraries);
  for (const library of dependencyOrder(
    graph,
    unpublished.map((entry) => entry.name),
  )) {
    await publishLibrary(deps, { library });
  }
  return deps.state.load();
}

/**
 * Publishes again, with what depends on them, the dev builds in the consumer's set that pin a sibling's
 * old dev version, so the set installs together (ADR 0014). Returns the state to install from.
 */
async function republishStaleBuilds(
  deps: CoreDeps,
  state: DryfitState,
  consumer: string,
): Promise<DryfitState> {
  const graph = await loadLibraryGraph(deps.fs, state.libraries);
  const set = linkedSet(state, consumer).map((entry) => entry.library.name);
  const stale = staleBuilds(state, graph, set);
  if (stale.length === 0) return state;
  for (const library of dependencyOrder(graph, publishSet(state, graph, stale))) {
    await publishLibrary(deps, { library });
  }
  return deps.state.load();
}

async function refuseWorkspaceMember(
  deps: CoreDeps,
  project: ProjectInfo,
  adapter: PackageManagerAdapter,
): Promise<void> {
  if (adapter.lockfiles.some((file) => project.rootFiles.includes(file))) return;
  const workspace = await enclosingWorkspace(deps.fs, project.root);
  if (workspace === undefined) return;
  throw new DryfitError(
    'not-a-consumer',
    `${project.root} is a package of the workspace at ${workspace}, whose lockfile an install there would change. dryfit links apps with their own lockfile.`,
    { consumer: project.root, workspace },
  );
}

/**
 * Taken when a consumer's first library is linked, replacing any leftover snapshot (from a restore
 * that was interrupted) because only the current files reflect what the user has committed since.
 * Later links into the same consumer must not take one: by then the files contain dryfit's edits.
 */
async function takeSnapshot(
  deps: CoreDeps,
  project: ProjectInfo,
  adapter: PackageManagerAdapter,
): Promise<void> {
  const dir = snapshotDir(deps, project.root);
  const lockfiles = adapter.lockfiles.filter((file) => project.rootFiles.includes(file));

  // Files that already hold a dev build (the app was linked under another spelling of its path, or
  // dryfit's state was lost) are not what the user committed; restoring them would bring the dev build back.
  const files = new Map<string, string>();
  const devBuild = new RegExp(DEV_VERSION_PATTERN);
  for (const file of ['package.json', ...lockfiles]) {
    const text = await deps.fs.readText(joinPath(project.root, file));
    if (text === undefined) continue;
    if (devBuild.test(text)) {
      throw new DryfitError(
        'consumer-linked',
        `${joinPath(project.root, file)} already holds a dryfit dev build. Restore the app, or put that file back with git, then link again.`,
        { consumer: project.root, file },
      );
    }
    files.set(file, text);
  }
  // Copies of the config files a live reload setting will be kept in, for restore to undo it (ADR 0007).
  const configFiles: string[] = [];
  for (const { file } of liveReloadFiles(project, deps.integrations)) {
    const text = await deps.fs.readText(joinPath(project.root, file));
    if (text === undefined) continue;
    files.set(joinPath('configs', file), text);
    configFiles.push(file);
  }

  await deps.fs.remove(dir);
  for (const [file, text] of files) await deps.fs.writeText(joinPath(dir, file), text);

  const meta: SnapshotMeta = {
    consumer: project.root,
    packageManager: adapter.name,
    lockfiles,
    createdAt: deps.clock.now().toISOString(),
    configFiles,
  };
  // meta.json is written last: its presence marks a complete snapshot.
  await deps.fs.writeText(joinPath(dir, 'meta.json'), `${JSON.stringify(meta, null, 2)}\n`);
}
