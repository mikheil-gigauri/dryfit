import type { FileSystem } from '../ports.ts';
import { isRecord, tryParseJson } from '../util/json.ts';
import { joinPath, relativeInside, resolvePath } from '../util/path.ts';
import { readManifest } from './manifest.ts';

export type LibraryBuildKind = 'nx' | 'angular' | 'npm-script' | 'none';

export interface DetectedLibraryBuild {
  readonly kind: LibraryBuildKind;
  /** Runs in the library root. Workspace CLIs are called by absolute path so npx never downloads one. */
  readonly build?: { readonly command: string; readonly args: readonly string[] };
  readonly publishDir: string;
}

/** How far up from a library to look for an Nx or Angular workspace. */
const MAX_WORKSPACE_DEPTH = 6;

/**
 * Works out how a library is built and what gets published, so `dryfit add` needs no flags for the
 * common cases: an Nx library, an Angular CLI library (both usually ng-packagr), or a package with a
 * `build` script. Flags passed by the user always win over this.
 */
export async function detectLibraryBuild(fs: FileSystem, root: string): Promise<DetectedLibraryBuild> {
  const libraryRoot = joinPath(root);
  const { manifest } = await readManifest(fs, libraryRoot);
  const ngPackage = await readJson(fs, joinPath(libraryRoot, 'ng-package.json'));
  // ng-packagr writes to `dist` beside ng-package.json unless `dest` says otherwise.
  const ngDest =
    ngPackage === undefined
      ? undefined
      : resolvePath(libraryRoot, typeof ngPackage.dest === 'string' ? ngPackage.dest : 'dist');

  const project = await readJson(fs, joinPath(libraryRoot, 'project.json'));
  const nxRoot = project && (await findUp(fs, libraryRoot, 'nx.json'));
  if (project && nxRoot !== undefined) {
    const name = typeof project.name === 'string' ? project.name : String(manifest.name);
    const projectRoot = relativeInside(nxRoot, libraryRoot) ?? '';
    return {
      kind: 'nx',
      build: { command: joinPath(nxRoot, 'node_modules/.bin/nx'), args: ['build', name] },
      publishDir: ngDest ?? nxOutputPath(project, nxRoot, projectRoot) ?? libraryRoot,
    };
  }

  // An Nx project without project.json: its targets come from package.json scripts or from plugins that
  // infer them, so Nx itself is asked to build it, by the name Nx gives such a project.
  const inferredRoot = project ? undefined : await findUp(fs, libraryRoot, 'nx.json');
  if (inferredRoot !== undefined && relativeInside(inferredRoot, libraryRoot)) {
    const nx = joinPath(inferredRoot, 'node_modules/.bin/nx');
    const nxField = isRecord(manifest.nx) ? manifest.nx : {};
    const targets = isRecord(nxField.targets) ? nxField.targets : {};
    const scripts = isRecord(manifest.scripts) ? manifest.scripts : {};
    // Only a library with a sign that it builds, and a workspace with nx installed, is handed to Nx.
    const pluginTarget = await pluginBuildTarget(fs, inferredRoot, libraryRoot);
    const builds =
      typeof scripts.build === 'string' ||
      'build' in targets ||
      ngPackage !== undefined ||
      pluginTarget !== undefined;
    if (builds && (await fs.exists(nx))) {
      const name = typeof nxField.name === 'string' ? nxField.name : String(manifest.name);
      const projectRoot = relativeInside(inferredRoot, libraryRoot) ?? '';
      // A plugin may call its target something else, but a build script or target of the project's own wins.
      const target =
        typeof scripts.build === 'string' || 'build' in targets ? 'build' : (pluginTarget ?? 'build');
      return {
        kind: 'nx',
        build: { command: nx, args: [target, name] },
        publishDir: ngDest ?? nxOutputPath(nxField, inferredRoot, projectRoot) ?? libraryRoot,
      };
    }
  }

  const angularRoot = await findUp(fs, libraryRoot, 'angular.json');
  if (angularRoot !== undefined) {
    const workspace = await readJson(fs, joinPath(angularRoot, 'angular.json'));
    const relative = relativeInside(angularRoot, libraryRoot);
    const projects = isRecord(workspace?.projects) ? workspace.projects : {};
    const match = Object.entries(projects).find(
      ([, config]) =>
        isRecord(config) &&
        typeof config.root === 'string' &&
        joinPath('/', config.root) === joinPath('/', relative ?? '-'),
    );
    if (match) {
      return {
        kind: 'angular',
        build: { command: joinPath(angularRoot, 'node_modules/.bin/ng'), args: ['build', match[0]] },
        publishDir: ngDest ?? libraryRoot,
      };
    }
  }

  const scripts = isRecord(manifest.scripts) ? manifest.scripts : {};
  if (typeof scripts.build === 'string') {
    return { kind: 'npm-script', build: { command: 'npm', args: ['run', 'build'] }, publishDir: libraryRoot };
  }
  return { kind: 'none', publishDir: libraryRoot };
}

/**
 * The Nx plugins that infer a build target from a config file in the project, with the option that can
 * rename it. A plugin infers nothing for a project without its config file, so the file is the sign.
 */
const BUILD_PLUGINS: ReadonlyArray<{
  readonly plugin: string;
  readonly files: readonly string[];
  readonly targetOption: (options: Record<string, unknown>) => unknown;
}> = [
  {
    plugin: '@nx/js/typescript',
    files: ['tsconfig.lib.json'],
    targetOption: (options) => (isRecord(options.build) ? options.build.targetName : undefined),
  },
  {
    plugin: '@nx/vite/plugin',
    files: ['vite.config.ts', 'vite.config.mts', 'vite.config.js', 'vite.config.mjs'],
    targetOption: (options) => options.buildTargetName,
  },
  {
    plugin: '@nx/rollup/plugin',
    files: ['rollup.config.ts', 'rollup.config.js', 'rollup.config.mjs', 'rollup.config.cjs'],
    targetOption: (options) => options.buildTargetName,
  },
  {
    plugin: '@nx/webpack/plugin',
    files: ['webpack.config.ts', 'webpack.config.js', 'webpack.config.cjs'],
    targetOption: (options) => options.buildTargetName,
  },
];

/** The name of the build target a plugin in nx.json infers for the library, if one does. */
async function pluginBuildTarget(
  fs: FileSystem,
  workspace: string,
  libraryRoot: string,
): Promise<string | undefined> {
  const nxJson = await readJson(fs, joinPath(workspace, 'nx.json'));
  const plugins = Array.isArray(nxJson?.plugins) ? nxJson.plugins : [];
  for (const entry of plugins) {
    const name = typeof entry === 'string' ? entry : isRecord(entry) ? entry.plugin : undefined;
    const known = BUILD_PLUGINS.find((candidate) => candidate.plugin === name);
    if (!known) continue;
    let present = false;
    for (const file of known.files) {
      if (await fs.exists(joinPath(libraryRoot, file))) {
        present = true;
        break;
      }
    }
    if (!present) continue;
    const options = isRecord(entry) && isRecord(entry.options) ? entry.options : {};
    const renamed = known.targetOption(options);
    return typeof renamed === 'string' && renamed !== '' ? renamed : 'build';
  }
  return undefined;
}

function nxOutputPath(
  project: Record<string, unknown>,
  workspace: string,
  projectRoot: string,
): string | undefined {
  const targets = isRecord(project.targets) ? project.targets : {};
  const build = isRecord(targets.build) ? targets.build : {};
  const options = isRecord(build.options) ? build.options : {};
  if (typeof options.outputPath !== 'string') return undefined;
  const path = options.outputPath
    .replaceAll('{workspaceRoot}', workspace)
    .replaceAll('{projectRoot}', projectRoot);
  return resolvePath(workspace, path);
}

async function findUp(fs: FileSystem, from: string, file: string): Promise<string | undefined> {
  let dir = from;
  for (let depth = 0; depth <= MAX_WORKSPACE_DEPTH; depth += 1) {
    if (await fs.exists(joinPath(dir, file))) return dir;
    if (dir === '/') return undefined;
    dir = joinPath(dir, '..');
  }
  return undefined;
}

async function readJson(fs: FileSystem, path: string): Promise<Record<string, unknown> | undefined> {
  const text = await fs.readText(path);
  const parsed = text === undefined ? undefined : tryParseJson(text);
  return isRecord(parsed) ? parsed : undefined;
}
