/**
 * The commit guard (ADR 0005, ADR 0012): a block of POSIX sh placed at the top of a consumer's
 * pre-commit hook. It refuses a commit when a staged manifest or lockfile mentions a dryfit dev
 * version, or a staged angular.json or project.json holds dryfit's live reload setting, which is
 * exactly what a linked consumer's files contain until they are restored.
 *
 * It needs neither Node nor dryfit at commit time, so it works from GUI git clients with a minimal
 * PATH and cannot break when dryfit is moved or uninstalled.
 */

const START = '# >>> dryfit commit guard >>>';
const END = '# <<< dryfit commit guard <<<';
const NEW_HOOK = '#!/bin/sh\n';

/** Matches a dev version as `nextDevVersion` writes it: `-dev.` or `.dev.` plus a 14-digit stamp. */
export const DEV_VERSION_PATTERN = '[-.]dev\\.[0-9]{14}';

/** Marks a dev server setting dryfit keeps while linked (ADR 0007), so the guard can find it. */
export const LINKED_MARKER = 'dryfit:linked';

const STAGED_FILES = [
  'package.json',
  'package-lock.json',
  'npm-shrinkwrap.json',
  'pnpm-lock.yaml',
  'yarn.lock',
  'bun.lock',
  'angular.json',
  'project.json',
]
  .map((name) => `':(glob)**/${name}'`)
  .join(' ');

/** Marks a hook file dryfit created itself, so restoring deletes it rather than leaving a stub. */
const CREATED = '# dryfit created this hook file; restoring deletes it.';

const BODY = [
  '# Added by `dryfit link`, removed by `dryfit restore`. Refuses commits that would ship a dev build.',
  // core.quotePath=false keeps non-ASCII paths readable by `git show`; git still quotes paths holding
  // tabs, newlines, quotes or backslashes, which no manifest or lockfile path is expected to contain.
  `dryfit_leaks=$(git -c core.quotePath=false diff --cached --name-only --diff-filter=ACMR -- ${STAGED_FILES} | while IFS= read -r dryfit_file; do`,
  `  if git show ":$dryfit_file" 2>/dev/null | grep -Eq -- '${DEV_VERSION_PATTERN}|"${LINKED_MARKER}"'; then printf '  %s\\n' "$dryfit_file"; fi`,
  'done)',
  'if [ -n "$dryfit_leaks" ]; then',
  `  printf 'dryfit: these staged files point at a local dev build:\\n%s\\n' "$dryfit_leaks" >&2`,
  "  printf 'Run `dryfit restore` in this project first, or commit with --no-verify if you are sure.\\n' >&2",
  '  exit 1',
  'fi',
];

const block = (created: boolean) => [START, ...(created ? [CREATED] : []), ...BODY, END].join('\n');

/** Lines that are verbatim dryfit's, for taking out a block whose end marker was edited away. */
const OWN_LINES = new Set([START, CREATED, ...BODY, END]);

export function hasGuard(hook: string | undefined): boolean {
  return hook?.includes(START) ?? false;
}

/** The hook with the guard as its first step. Applying it again replaces the old block. */
export function withGuard(hook: string | undefined): string {
  const base = hook === undefined ? undefined : withoutGuard(hook);
  if (base === undefined) return `${NEW_HOOK}${block(true)}\n`;
  if (!base.startsWith('#!')) return `${block(false)}\n${base}`;

  const newline = base.indexOf('\n');
  const shebang = newline === -1 ? `${base}\n` : base.slice(0, newline + 1);
  const rest = newline === -1 ? '' : base.slice(newline + 1);
  return `${shebang}${block(false)}\n${rest}`;
}

/**
 * The hook without the guard, exactly as it was before; undefined when dryfit created the file and
 * nothing but a shebang would remain. If the end marker is gone, only lines that are verbatim
 * dryfit's are taken out, so the user's own hook lines are never removed.
 */
export function withoutGuard(hook: string): string | undefined {
  const start = hook.indexOf(START);
  if (start === -1) return hook;
  const endMarker = hook.indexOf(END, start);
  let end = endMarker + END.length;
  if (endMarker === -1) {
    const lines = hook.slice(start).split('\n');
    const own = lines.findIndex((line) => !OWN_LINES.has(line));
    end = start + lines.slice(0, own === -1 ? lines.length : own).join('\n').length;
  }
  if (hook[end] === '\n') end += 1;

  const created = hook.slice(start, end).includes(CREATED);
  const rest = hook.slice(0, start) + hook.slice(end);
  return created && /^(#![^\n]*\n?)?\s*$/.test(rest) ? undefined : rest;
}
