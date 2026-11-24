#!/usr/bin/env node
// Writes the menu bar app's design tokens (apps/menubar/tokens.json) out to where they're used:
//   - Sources/DryfitMenu/UI/Tokens.swift, the `Theme` colours and radii the views draw with;
//   - the block between `tokens:begin` and `tokens:end` in every mock listed in `$css.files`, so a mock
//     and the app read the same values and can't drift apart.
//
//   node apps/menubar/scripts/tokens.mjs           write both
//   node apps/menubar/scripts/tokens.mjs --check   change nothing; exit 1 if either is out of date (CI)
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const app = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repo = resolve(app, '../..');
const tokens = JSON.parse(readFileSync(join(app, 'tokens.json'), 'utf8'));
const check = process.argv.includes('--check');

/** "#rrggbb" or "#rrggbb / 0.5" → { hex: "rrggbb", alpha: 0.5 } */
function parse(value, where) {
  const m = /^#([0-9a-f]{6})(?:\s*\/\s*([0-9.]+))?$/i.exec(value);
  if (!m) throw new Error(`${where}: "${value}" isn't #rrggbb or #rrggbb / <alpha>`);
  return { hex: m[1].toLowerCase(), alpha: m[2] === undefined ? 1 : Number(m[2]), text: m[2] };
}

function swift() {
  const lines = [
    '// Generated from apps/menubar/tokens.json by `npm run menubar:tokens`. Don’t edit: change tokens.json.',
    'import SwiftUI',
    '',
    'extension Theme {',
  ];
  for (const [name, t] of Object.entries(tokens.color)) {
    const l = parse(t.light, name),
      d = parse(t.dark, name);
    for (const c of t.comment?.split('\n') ?? []) lines.push(`  /// ${c}`);
    const alpha = l.alpha === 1 && d.alpha === 1 ? '' : `, light: ${l.text ?? '1'}, dark: ${d.text ?? '1'}`;
    lines.push(`  static let ${name} = color(0x${l.hex}, 0x${d.hex}${alpha})`);
  }
  lines.push('');
  for (const [name, t] of Object.entries(tokens.radius))
    lines.push(`  static let ${name}: CGFloat = ${t.value}`);
  lines.push('}', '');
  return lines.join('\n');
}

function css(value) {
  const { hex, alpha } = parse(value, 'css');
  if (alpha === 1) return `#${hex}`;
  const [r, g, b] = [0, 2, 4].map((i) => Number.parseInt(hex.slice(i, i + 2), 16));
  return `rgba(${r},${g},${b},${String(alpha).replace(/^0\./, '.')})`;
}

function cssBlock() {
  const colors = Object.values(tokens.color).filter((t) => t.css);
  const light = colors.map((t) => `${t.css}:${css(t.light)};`);
  const radii = Object.values(tokens.radius)
    .filter((t) => t.css)
    .map((t) => `${t.css}:${t.value}px;`);
  const dark = colors.map((t) => `${t.css}:${css(t.dark)};`);
  return [
    '/* tokens:begin: generated from apps/menubar/tokens.json by `npm run menubar:tokens`; edit that, not this */',
    `${tokens.$css.light}{${[...light, ...radii].join('')}}`,
    `${tokens.$css.dark}{${dark.join('')}}`,
    '/* tokens:end */',
  ].join('\n');
}

const stale = [];
function write(path, content) {
  const before = readFileSync(path, 'utf8');
  if (before === content) return;
  if (check) stale.push(path);
  else {
    writeFileSync(path, content);
    process.stdout.write(`wrote ${path.slice(repo.length + 1)}\n`);
  }
}

write(join(app, 'Sources/DryfitMenu/UI/Tokens.swift'), swift());
const block = cssBlock();
for (const file of tokens.$css.files) {
  const path = join(repo, file);
  const html = readFileSync(path, 'utf8');
  const pattern = /\/\* tokens:begin[\s\S]*?tokens:end \*\//;
  if (!pattern.test(html)) throw new Error(`${file} has no /* tokens:begin */ … /* tokens:end */ block`);
  write(
    path,
    html.replace(pattern, () => block),
  );
}
if (stale.length) {
  process.stderr.write(
    `out of date with apps/menubar/tokens.json: ${stale.map((p) => p.slice(repo.length + 1)).join(', ')}` +
      '\n',
  );
  process.stderr.write('run `npm run menubar:tokens` and commit the result\n');
  process.exit(1);
}
