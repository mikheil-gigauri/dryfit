import type { LibraryRecord } from '../model.ts';
import type { FileSystem } from '../ports.ts';
import { isRecord, tryParseJson } from '../util/json.ts';
import { joinPath } from '../util/path.ts';

/** The fields a consumer installs from, and so the ones whose pins a dev build must get right (ADR 0014). */
export const RUNTIME_DEPENDENCY_FIELDS = [
  'dependencies',
  'peerDependencies',
  'optionalDependencies',
] as const;

/** For each registered library, the registered libraries it depends on directly. */
export type LibraryGraph = ReadonlyMap<string, ReadonlySet<string>>;

/**
 * Reads which registered libraries depend on which, from each library's own package.json and its
 * publish folder's (ADR 0014). A manifest that is missing or unreadable adds no edges: the graph only
 * decides what else to publish, install or restore, never whether a library can be used.
 */
export async function loadLibraryGraph(
  fs: FileSystem,
  libraries: readonly LibraryRecord[],
): Promise<LibraryGraph> {
  const names = new Set(libraries.map((library) => library.name));
  const graph = new Map<string, ReadonlySet<string>>();
  for (const library of libraries) {
    const dependencies = await runtimeDependencies(fs, library);
    graph.set(library.name, new Set([...dependencies].filter((name) => names.has(name))));
  }
  return graph;
}

/** Every package a library's own package.json or its publish folder's names in a runtime field. */
export async function runtimeDependencies(fs: FileSystem, library: LibraryRecord): Promise<Set<string>> {
  const dependencies = new Set<string>();
  for (const dir of new Set([library.root, library.publishDir])) {
    const text = await fs.readText(joinPath(dir, 'package.json'));
    const manifest = text === undefined ? undefined : tryParseJson(text);
    if (!isRecord(manifest)) continue;
    for (const field of RUNTIME_DEPENDENCY_FIELDS) {
      const entries = manifest[field];
      if (!isRecord(entries)) continue;
      for (const name of Object.keys(entries)) if (name !== library.name) dependencies.add(name);
    }
  }
  return dependencies;
}

/** Every library that depends on `name`, directly or through others. */
export function dependentsOf(graph: LibraryGraph, name: string): Set<string> {
  return reach(name, (current) =>
    [...graph].filter(([, edges]) => edges.has(current)).map(([dependent]) => dependent),
  );
}

/** Every library `name` depends on, directly or through others. */
export function dependenciesOf(graph: LibraryGraph, name: string): Set<string> {
  return reach(name, (current) => [...(graph.get(current) ?? [])]);
}

/** Every library tied to `name` by dependencies in either direction, `name` included. */
export function connectedTo(graph: LibraryGraph, name: string): Set<string> {
  const tied = reach(name, (current) => [
    ...(graph.get(current) ?? []),
    ...[...graph].filter(([, edges]) => edges.has(current)).map(([other]) => other),
  ]);
  return tied.add(name);
}

/**
 * `names` with every library after the ones it depends on, so each dev build can pin the versions
 * published just before it. Ties keep name order; libraries in a cycle come last, in name order.
 */
export function dependencyOrder(graph: LibraryGraph, names: Iterable<string>): string[] {
  const pending = new Set([...names].sort());
  const ordered: string[] = [];
  for (;;) {
    const ready = [...pending].filter((name) =>
      [...(graph.get(name) ?? [])].every((dependency) => !pending.has(dependency)),
    );
    if (ready.length === 0) break;
    for (const name of ready) {
      ordered.push(name);
      pending.delete(name);
    }
  }
  return [...ordered, ...pending];
}

function reach(start: string, next: (name: string) => readonly string[]): Set<string> {
  const seen = new Set<string>();
  const queue = [start];
  for (let current = queue.shift(); current !== undefined; current = queue.shift()) {
    for (const name of next(current)) {
      if (name === start || seen.has(name)) continue;
      seen.add(name);
      queue.push(name);
    }
  }
  return seen;
}
