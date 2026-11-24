import type { FileSystem } from '../ports.ts';
import { isRecord, tryParseJson } from '../util/json.ts';
import { joinPath } from '../util/path.ts';
import { enclosingWorkspace } from './load-project.ts';

/** How deep below a workspace root its packages are looked for. */
const MAX_PACKAGE_DEPTH = 4;
/** Folders that hold dependencies or build output, never a workspace's own packages. */
const SKIPPED = new Set(['node_modules', 'dist', 'build', 'out', 'tmp', 'coverage']);

/**
 * The root of the npm, pnpm, Yarn, Bun or Nx workspace that holds `dir`, if any. Nx workspaces often
 * declare no package globs, so their `nx.json` counts too.
 */
export async function workspaceRootOf(fs: FileSystem, dir: string): Promise<string | undefined> {
  const declared = await enclosingWorkspace(fs, dir);
  if (declared !== undefined) return declared;
  let current = joinPath(dir);
  while (current !== '/') {
    current = joinPath(current, '..');
    if (await fs.exists(joinPath(current, 'nx.json'))) return current;
  }
  return undefined;
}

/**
 * The folders of the packages below a workspace root whose names are in `names`, the shallowest one
 * for each name. Hidden folders, dependencies and build output are skipped.
 */
export async function findWorkspacePackages(
  fs: FileSystem,
  root: string,
  names: ReadonlySet<string>,
): Promise<Map<string, string>> {
  const found = new Map<string, string>();
  let level = [joinPath(root)];
  for (let depth = 0; depth <= MAX_PACKAGE_DEPTH && level.length > 0 && found.size < names.size; depth++) {
    const next: string[] = [];
    for (const dir of level) {
      if (depth > 0) {
        const text = await fs.readText(joinPath(dir, 'package.json'));
        const manifest = text === undefined ? undefined : tryParseJson(text);
        const name = isRecord(manifest) ? manifest.name : undefined;
        if (typeof name === 'string' && names.has(name) && !found.has(name)) found.set(name, dir);
      }
      for (const entry of await fs.readDir(dir))
        if (entry.isDirectory && !entry.name.startsWith('.') && !SKIPPED.has(entry.name))
          next.push(joinPath(dir, entry.name));
    }
    level = next;
  }
  return found;
}
