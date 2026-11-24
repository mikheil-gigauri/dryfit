import { describe, expect, it } from 'vitest';
import { createScenario, HOME, json, LIB, SHOP, scenarioFiles } from '../../testing/scenario.ts';
import type { DryfitState } from '../model.ts';
import type { DryfitEvent } from '../ports.ts';
import { linkConsumer } from './link-consumer.ts';
import { restoreConsumer } from './restore-consumer.ts';
import { snapshotDir } from './shared.ts';
import { syncLibrary } from './sync-library.ts';

// ADR 0007: while linked, the shop's dev server keeps the library out of its pre-bundle, so a running
// server rebuilds from each install instead of serving what it pre-bundled when it started.

const registered: DryfitState = {
  libraries: [{ name: '@acme/ui', root: LIB, publishDir: `${LIB}/dist/ui` }],
  links: [],
  groups: [],
};

/** The shop's angular.json, with a dev server, laid out by hand rather than by JSON.stringify. */
const ANGULAR_JSON = [
  '{',
  '    "version": 1,',
  '    "projects": {',
  '        "shop": {',
  '            "architect": {',
  '                "serve": {',
  '                    "builder": "@angular/build:dev-server",',
  '                    "options": { "port": 4200 }',
  '                }',
  '            }',
  '        }',
  '    }',
  '}',
  '',
].join('\n');

function shopWithDevServer() {
  return createScenario({
    state: registered,
    files: { ...scenarioFiles(), [`${SHOP}/angular.json`]: ANGULAR_JSON },
  });
}

const cleared = (events: readonly DryfitEvent[]) =>
  events.flatMap((event) => (event.type === 'caches:cleared' ? [event.consumer] : []));

const prebundle = (text: string | undefined) =>
  JSON.parse(text ?? '{}').projects.shop.architect.serve.options.prebundle as unknown;

describe('live reload of an Angular dev server', () => {
  it('turns on when the app is linked, and asks for one restart to pick it up', async () => {
    const { deps, fs, events } = shopWithDevServer();

    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    expect(prebundle(await fs.readText(`${SHOP}/angular.json`))).toEqual({
      exclude: ['@acme/ui', 'dryfit:linked'],
    });
    expect(cleared(events.events)).toEqual([SHOP]);
  });

  it('lets later installs reach the running dev server, with no caches cleared and no restart asked', async () => {
    const { deps, fs, events } = shopWithDevServer();
    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });
    await fs.writeText(`${SHOP}/.angular/cache/20.1.3/vite/deps/chunk.js`, 'served by the running server');
    events.events.length = 0;

    const result = await syncLibrary(deps, { library: '@acme/ui' });

    expect(result.installs).toEqual([
      expect.objectContaining({ consumer: SHOP, ok: true, clearedCaches: [] }),
    ]);
    expect(cleared(events.events)).toEqual([]);
    expect(await fs.exists(`${SHOP}/.angular/cache/20.1.3/vite/deps/chunk.js`)).toBe(true);
  });

  it('puts angular.json back byte for byte on restore', async () => {
    const { deps, fs } = shopWithDevServer();
    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });
    await syncLibrary(deps, { library: '@acme/ui' });

    expect(await restoreConsumer(deps, { consumer: SHOP })).toEqual({ ok: true });

    expect(await fs.readText(`${SHOP}/angular.json`)).toBe(ANGULAR_JSON);
  });

  it('keeps changes the user made to angular.json while linked', async () => {
    const { deps, fs } = shopWithDevServer();
    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });
    const linked = (await fs.readText(`${SHOP}/angular.json`)) ?? '';
    await fs.writeText(`${SHOP}/angular.json`, linked.replace('"port": 4200', '"port": 4300'));

    expect(await restoreConsumer(deps, { consumer: SHOP })).toEqual({ ok: true });

    expect(await fs.readText(`${SHOP}/angular.json`)).toBe(ANGULAR_JSON.replace('4200', '4300'));
  });

  it('refuses to restore an angular.json that no longer parses, unless forced', async () => {
    const { deps, fs } = shopWithDevServer();
    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });
    const manifest = await fs.readText(`${SHOP}/package.json`);
    await fs.writeText(`${SHOP}/angular.json`, '{ "projects": ');

    await expect(restoreConsumer(deps, { consumer: SHOP })).rejects.toMatchObject({
      code: 'manifest-drifted',
    });
    expect(await fs.readText(`${SHOP}/package.json`)).toBe(manifest);

    expect(await restoreConsumer(deps, { consumer: SHOP, force: true })).toEqual({ ok: true });
    expect(await fs.readText(`${SHOP}/angular.json`)).toBe(ANGULAR_JSON);
  });

  it('leaves the dev server alone for an app linked by an older dryfit, whose snapshot cannot undo it', async () => {
    const { deps, fs } = createScenario({
      state: { ...registered, links: [{ library: '@acme/ui', consumer: SHOP, status: 'installed' }] },
      files: {
        ...scenarioFiles(),
        [`${SHOP}/angular.json`]: ANGULAR_JSON,
        [`${snapshotDir({ home: HOME }, SHOP)}/package.json`]: json({ name: 'shop' }),
        [`${snapshotDir({ home: HOME }, SHOP)}/meta.json`]: json({
          consumer: SHOP,
          packageManager: 'npm',
          lockfiles: [],
          createdAt: '2026-11-18T12:00:00.000Z',
        }),
      },
    });

    await syncLibrary(deps, { library: '@acme/ui' });

    expect(await fs.readText(`${SHOP}/angular.json`)).toBe(ANGULAR_JSON);
  });
});
