import {
  applyEdits,
  findNodeAtLocation,
  getNodeValue,
  modify,
  type Node,
  type ParseError,
  parseTree,
} from 'jsonc-parser';
import { LINKED_MARKER } from '../../core/guard/commit-guard.ts';
import type { ConsumerIntegration, LiveReloadSetting } from '../../core/ports.ts';
import { dependsOnAny } from '../../core/project/cache-paths.ts';
import { detectIndent, isRecord } from '../../core/util/json.ts';

const DEFAULT_CACHE = '.angular/cache';

/** The Angular CLI's Vite dev server, under both packages that ship it. Nx runs them as executors. */
const DEV_SERVERS = new Set(['@angular/build:dev-server', '@angular-devkit/build-angular:dev-server']);

type JsonPath = (string | number)[];

/**
 * The dev server pre-bundles every dependency once, when it starts, and never looks at node_modules
 * again; a library kept out of the pre-bundle is built with the app instead, from files the dev server
 * watches. So dryfit adds linked libraries to `prebundle.exclude` of every dev server target, with a
 * mark the commit guard refuses (ADR 0007).
 */
const liveReload: LiveReloadSetting = {
  files: ['angular.json', 'project.json'],

  apply(text, libraries) {
    const tree = readTree(text);
    if (tree === undefined) return undefined;
    let edited = text;
    for (const path of prebundlePaths(tree)) {
      const value = valueAt(edited, path);
      if (value === undefined || value === true) {
        edited = setValue(edited, path, { exclude: [...libraries, LINKED_MARKER] }) ?? edited;
      } else if (isRecord(value) && (value.exclude === undefined || Array.isArray(value.exclude))) {
        const existing = (value.exclude ?? []) as unknown[];
        const exclude = [
          ...existing.filter((name) => name !== LINKED_MARKER),
          ...libraries.filter((name) => !existing.includes(name)),
          LINKED_MARKER,
        ];
        if (JSON.stringify(exclude) !== JSON.stringify(existing)) {
          edited = setValue(edited, [...path, 'exclude'], exclude) ?? edited;
        }
      }
      // `false` pre-bundles nothing, so the dev server already rebuilds from node_modules.
    }
    return edited === text ? undefined : edited;
  },

  isOn(text, libraries) {
    const tree = readTree(text);
    if (tree === undefined) return false;
    const marked = prebundlePaths(tree).some((path) => {
      const value = valueAt(text, path);
      return isRecord(value) && Array.isArray(value.exclude) && value.exclude.includes(LINKED_MARKER);
    });
    return marked && liveReload.apply(text, libraries) === undefined;
  },

  revert(current, original, libraries) {
    const tree = readTree(current);
    if (tree === undefined) return undefined;
    if (current === (liveReload.apply(original, libraries) ?? original)) return original;
    let reverted = current;
    for (const path of prebundlePaths(tree)) {
      const before = valueAt(original, path);
      if (JSON.stringify(valueAt(reverted, path)) === JSON.stringify(before)) continue;
      reverted = setValue(reverted, path, before) ?? reverted;
    }
    return reverted;
  },
};

/**
 * The Angular CLI pre-bundles dependencies (Vite/esbuild) into its persistent cache, which outlives
 * an install. The location can be moved with `cli.cache.path` in angular.json.
 */
export const angular: ConsumerIntegration = {
  id: 'angular',
  configFiles: ['angular.json'],

  detect: (project) => project.rootFiles.includes('angular.json') || dependsOnAny(project, ['@angular/core']),

  cachePaths(project) {
    const config = project.configs.get('angular.json');
    const cli = isRecord(config) ? config.cli : undefined;
    const cache = isRecord(cli) ? cli.cache : undefined;
    const path = isRecord(cache) ? cache.path : undefined;
    return [typeof path === 'string' && path.length > 0 ? path : DEFAULT_CACHE];
  },

  liveReload,
};

/** The file's syntax tree; undefined when it has errors. Comments and trailing commas are allowed, as the Angular CLI allows them. */
function readTree(text: string): Node | undefined {
  const errors: ParseError[] = [];
  const tree = parseTree(text, errors, { allowTrailingComma: true });
  return errors.length === 0 && tree?.type === 'object' ? tree : undefined;
}

function valueAt(text: string, path: JsonPath): unknown {
  const tree = readTree(text);
  const node = tree && findNodeAtLocation(tree, path);
  return node === undefined ? undefined : getNodeValue(node);
}

/**
 * Where a dev server target's `prebundle` lives: its options, and each configuration that sets its
 * own (it overrides the options). Targets sit in `projects.*.architect` (Angular CLI), or
 * `projects.*.targets` and a project.json's `targets` (Nx).
 */
function prebundlePaths(tree: Node): JsonPath[] {
  const config = getNodeValue(tree) as Record<string, unknown>;
  const targets: [JsonPath, unknown][] = [];
  const add = (path: JsonPath, group: unknown) => {
    if (isRecord(group))
      for (const [name, target] of Object.entries(group)) targets.push([[...path, name], target]);
  };
  if (isRecord(config.projects)) {
    for (const [name, project] of Object.entries(config.projects)) {
      if (!isRecord(project)) continue;
      add(['projects', name, 'architect'], project.architect);
      add(['projects', name, 'targets'], project.targets);
    }
  }
  add(['targets'], config.targets);

  return targets.flatMap(([path, target]) => {
    if (!isRecord(target) || !DEV_SERVERS.has(String(target.builder ?? target.executor))) return [];
    const configurations = isRecord(target.configurations) ? Object.entries(target.configurations) : [];
    return [
      [...path, 'options', 'prebundle'],
      ...configurations.flatMap(([name, configuration]) =>
        isRecord(configuration) && configuration.prebundle !== undefined
          ? [[...path, 'configurations', name, 'prebundle']]
          : [],
      ),
    ];
  });
}

/**
 * `text` with the value at `path` set, or removed when `value` is undefined, leaving every other byte
 * alone. New values follow the layout around them: on one line inside a one-line object, else one
 * entry per line at the surrounding indent. Undefined when the path runs through something that is not
 * an object.
 */
function setValue(text: string, path: JsonPath, value: unknown): string | undefined {
  if (value === undefined) return applyEdits(text, modify(text, path, undefined, {}));
  const tree = readTree(text);
  if (tree === undefined) return undefined;

  const node = findNodeAtLocation(tree, path);
  if (node !== undefined) {
    const nested = node.parent?.type === 'property' ? node.parent : node;
    return splice(
      text,
      node.offset,
      node.length,
      format(text, value, isOneLine(text, node), indentAt(text, nested.offset)),
    );
  }

  const key = path.at(-1);
  const parentPath = path.slice(0, -1);
  if (typeof key !== 'string') return undefined;
  const parent = findNodeAtLocation(tree, parentPath);
  if (parent === undefined)
    return parentPath.length === 0 ? undefined : setValue(text, parentPath, { [key]: value });
  if (parent.type !== 'object') return undefined;

  const properties = parent.children ?? [];
  const last = properties.at(-1);
  if (last === undefined) {
    const indent = indentAt(text, parent.offset);
    return splice(
      text,
      parent.offset,
      parent.length,
      format(text, { [key]: value }, isOneLine(text, parent), indent),
    );
  }
  const end = last.offset + last.length;
  if (isOneLine(text, parent))
    return splice(text, end, 0, `, ${JSON.stringify(key)}: ${format(text, value, true, '')}`);
  const indent = indentAt(text, last.offset);
  return splice(
    text,
    end,
    0,
    `,${eolOf(text)}${indent}${JSON.stringify(key)}: ${format(text, value, false, indent)}`,
  );
}

function format(text: string, value: unknown, oneLine: boolean, indent: string): string {
  if (oneLine) return inline(value);
  return JSON.stringify(value, null, detectIndent(text)).replace(/\n/g, `${eolOf(text)}${indent}`);
}

function inline(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(inline).join(', ')}]`;
  if (!isRecord(value)) return JSON.stringify(value);
  const entries = Object.entries(value).map(([key, nested]) => `${JSON.stringify(key)}: ${inline(nested)}`);
  return entries.length === 0 ? '{}' : `{ ${entries.join(', ')} }`;
}

function isOneLine(text: string, node: Node): boolean {
  return !text.slice(node.offset, node.offset + node.length).includes('\n');
}

/** The leading whitespace of the line `offset` is on. */
function indentAt(text: string, offset: number): string {
  const start = text.lastIndexOf('\n', offset - 1) + 1;
  return /^[ \t]*/.exec(text.slice(start))?.[0] ?? '';
}

function eolOf(text: string): string {
  return text.includes('\r\n') ? '\r\n' : '\n';
}

function splice(text: string, offset: number, length: number, insert: string): string {
  return text.slice(0, offset) + insert + text.slice(offset + length);
}
