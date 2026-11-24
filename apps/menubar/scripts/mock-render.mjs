#!/usr/bin/env node
// Renders states of the approved mock (docs/design/dryfit-states.html) to PNG at 2x, light and dark, with
// only the drawn surface showing (the widget's `.panel`, the window's `.win`, the failures window's `.fw`)
// at the top left on white: <out>/<state>.<light|dark>.png. scripts/compare.sh puts each next to the
// app's render of the same scene (Tests/DryfitMenuTests/Snapshots.swift).
//
//   node apps/menubar/scripts/mock-render.mjs <out dir> [state ...]     every state when none is given
//
// Needs a Chromium: $CHROME, Google Chrome, or Playwright's download.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const out = resolve(process.argv[2] ?? 'apps/menubar/.build/compare/mock');
const only = process.argv.slice(3);
const html = readFileSync(join(repo, process.env.MOCK_FILE ?? 'docs/design/dryfit-states.html'), 'utf8');
const states = [...html.matchAll(/<section id="([^"]+)">/g)]
  .map((m) => m[1])
  .filter((id) => only.length === 0 || only.includes(id));

function chrome() {
  if (process.env.CHROME) return process.env.CHROME;
  const candidates = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'];
  const pw = join(homedir(), 'Library/Caches/ms-playwright');
  if (existsSync(pw)) {
    for (const d of readdirSync(pw)
      .filter((d) => d.startsWith('chromium-'))
      .sort()
      .reverse()) {
      for (const arch of ['chrome-mac-arm64', 'chrome-mac']) {
        candidates.push(join(pw, d, arch, 'Chromium.app/Contents/MacOS/Chromium'));
        candidates.push(
          join(pw, d, arch, 'Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'),
        );
      }
    }
  }
  const found = candidates.find(existsSync);
  if (!found) {
    process.stderr.write('mock-render: no Chromium found; set CHROME\n');
    process.exit(1);
  }
  return found;
}

// Only the state's surface, flat on white at the top left: no desk, no notes, no shadow, nothing moving.
// The viewport is wide so the page lays the surface out whole before it's moved; the PNG is cropped to
// the app's size when compared.
function page(id, theme) {
  const css = `<style>
html,body{background:#fff!important;margin:0!important;padding:0!important;min-height:0!important}
section{display:none!important} #${id}{display:block!important}
body *{visibility:hidden!important}
.__target,.__target *{visibility:visible!important}
.__target{box-shadow:none!important;margin:0!important}
/* The widget's glass sits on what the app's scene puts under it (LiveScenes.widget), not on the white page. */
.panel.__target{backdrop-filter:none!important;background:linear-gradient(var(--glass),var(--glass)),#f5f6fa!important}
body:has(#th-d:checked) .panel.__target{background:linear-gradient(var(--glass),var(--glass)),#242429!important}
*,*::before,*::after{animation:none!important;transition:none!important}
</style>`;
  // The surface is moved, not re-parented, so every selector that styles it still matches.
  const script = `<script>
const el = document.querySelector('#${id} .panel, #${id} .win, #${id} .fw, #${id} .stack');
if (el) {
  el.classList.add('__target');
  const r = el.getBoundingClientRect();
  document.body.style.transformOrigin = '0 0';
  document.body.style.transform = 'translate(' + (-r.left) + 'px,' + (-r.top) + 'px)';
}
</script>`;
  let doc = html.replace('</head>', `${css}</head>`).replace('</body>', `${script}</body>`);
  if (theme === 'dark')
    doc = doc.replace('id="th-l" checked', 'id="th-l"').replace('id="th-d"', 'id="th-d" checked');
  return doc;
}

const bin = chrome();
mkdirSync(out, { recursive: true });
const tmp = join(tmpdir(), `mock-render-${process.pid}`);
mkdirSync(tmp, { recursive: true });
for (const id of states) {
  for (const theme of ['light', 'dark']) {
    const file = join(tmp, `${id}.${theme}.html`);
    writeFileSync(file, page(id, theme));
    const png = join(out, `${id}.${theme}.png`);
    execFileSync(
      bin,
      [
        '--headless',
        '--disable-gpu',
        '--hide-scrollbars',
        '--force-device-scale-factor=2',
        '--window-size=2400,1400',
        `--screenshot=${png}`,
        '--virtual-time-budget=500',
        `file://${file}`,
      ],
      { stdio: 'ignore' },
    );
    process.stdout.write(`${id}.${theme} `);
  }
}
rmSync(tmp, { recursive: true, force: true });
process.stdout.write(`\n${states.length * 2} mock renders in ${out}\n`);
