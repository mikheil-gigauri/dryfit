import { describe, expect, it } from 'vitest';
import { failed } from '../../testing/fakes.ts';
import {
  ADMIN,
  createScenario,
  HOME,
  json,
  LIB,
  lockfileFor,
  SHOP,
  scenarioFiles,
  shopManifest,
} from '../../testing/scenario.ts';
import type { DryfitState } from '../model.ts';
import { pathSlug } from '../util/path.ts';
import { linkConsumer } from './link-consumer.ts';
import { restoreConsumer } from './restore-consumer.ts';
import { syncLibrary } from './sync-library.ts';

const registered: DryfitState = {
  libraries: [{ name: '@acme/ui', root: LIB, publishDir: `${LIB}/dist/ui` }],
  links: [],
  groups: [],
};

/** Links `consumers`, publishes and installs, returning the scenario mid-development. */
async function linkedAndSynced(
  consumers: string[],
  configure?: (s: ReturnType<typeof createScenario>) => void,
) {
  const scenario = createScenario({ state: registered });
  configure?.(scenario);
  for (const consumer of consumers) await linkConsumer(scenario.deps, { library: '@acme/ui', consumer });
  await syncLibrary(scenario.deps, { library: '@acme/ui' });
  return scenario;
}

const manifestAndLock = (files: Record<string, string>, root: string) => ({
  manifest: files[`${root}/package.json`],
  lockfile: files[`${root}/package-lock.json`],
});

describe('restoreConsumer', () => {
  it('puts the manifest and lockfile back byte for byte and reinstalls from the lockfile', async () => {
    const original = createScenario().fs.snapshot(SHOP);
    const { deps, fs, process } = await linkedAndSynced([SHOP]);
    expect(await fs.readText(`${SHOP}/package.json`)).not.toBe(original[`${SHOP}/package.json`]);

    const result = await restoreConsumer(deps, { consumer: SHOP });

    expect(result).toEqual({ ok: true });
    expect(manifestAndLock(fs.snapshot(SHOP), SHOP)).toEqual(manifestAndLock(original, SHOP));
    expect(process.lines(SHOP).at(-1)).toBe('npm install --no-audit --no-fund');
  });

  describe('choosing the install', () => {
    // The scenario's app has node_modules, as a developer's does.
    it('installs only what differs from the lockfile when node_modules is there', async () => {
      const { deps, process } = await linkedAndSynced([SHOP]);

      expect(await restoreConsumer(deps, { consumer: SHOP })).toEqual({ ok: true });

      expect(process.lines(SHOP).at(-1)).toBe('npm install --no-audit --no-fund');
    });

    it('installs everything from the lockfile when there is no node_modules', async () => {
      const { deps, fs, process } = await linkedAndSynced([SHOP]);
      await fs.remove(`${SHOP}/node_modules`);

      expect(await restoreConsumer(deps, { consumer: SHOP })).toEqual({ ok: true });

      expect(process.lines(SHOP).at(-1)).toBe('npm ci --no-audit --no-fund');
    });

    it('runs the full clean install when the incremental one fails', async () => {
      const { deps, process } = await linkedAndSynced([SHOP]);
      process.on('npm install --no-audit', failed('npm error ERESOLVE'));

      expect(await restoreConsumer(deps, { consumer: SHOP })).toEqual({ ok: true });

      expect(process.lines(SHOP).slice(-2)).toEqual([
        'npm install --no-audit --no-fund',
        'npm ci --no-audit --no-fund',
      ]);
    });

    it('reports the full install’s failure when both fail', async () => {
      const { deps, process } = await linkedAndSynced([SHOP]);
      process.on('npm install --no-audit', failed('npm error first'));
      process.on('npm ci', failed('npm error second'));

      expect(await restoreConsumer(deps, { consumer: SHOP })).toEqual({
        ok: false,
        output: 'npm error second',
      });
    });

    it('puts a lockfile the install rewrote back to the snapshot, byte for byte', async () => {
      const original = createScenario().fs.snapshot(SHOP);
      const { deps, fs, process } = await linkedAndSynced([SHOP]);
      process.on('npm install --no-audit', async (spec) => {
        await fs.writeText(`${spec.cwd}/package-lock.json`, '{"lockfileVersion": 3, "rewritten": true}\n');
        return { exitCode: 0, stdout: '', stderr: '' };
      });

      await restoreConsumer(deps, { consumer: SHOP });

      expect(manifestAndLock(fs.snapshot(SHOP), SHOP)).toEqual(manifestAndLock(original, SHOP));
    });
  });

  it('restores a consumer whose install failed half-way (M1 exit check)', async () => {
    const original = createScenario().fs.snapshot(SHOP);
    const { deps, fs, store } = await linkedAndSynced([SHOP], ({ npm }) => npm.failIn(SHOP));
    expect(store.current.links[0]?.status).toBe('failed');
    expect(await fs.readText(`${SHOP}/package.json`)).not.toBe(original[`${SHOP}/package.json`]);

    await restoreConsumer(deps, { consumer: SHOP });

    expect(manifestAndLock(fs.snapshot(SHOP), SHOP)).toEqual(manifestAndLock(original, SHOP));
  });

  it('removes a lockfile that npm created when the consumer had none', async () => {
    const { deps, fs, process } = await linkedAndSynced([ADMIN]);
    expect(await fs.exists(`${ADMIN}/package-lock.json`)).toBe(true);

    await restoreConsumer(deps, { consumer: ADMIN });

    expect(await fs.exists(`${ADMIN}/package-lock.json`)).toBe(false);
    expect(process.lines(ADMIN).at(-1)).toBe('npm install --no-package-lock --no-audit --no-fund');
  });

  it('removes a lockfile the clean install itself created when the consumer had none', async () => {
    // Yarn Berry, for one, always writes a lockfile on install.
    const { deps, fs, process } = await linkedAndSynced([ADMIN]);
    process.on('npm install --no-package-lock', async (spec) => {
      await fs.writeText(`${spec.cwd}/package-lock.json`, '{}\n');
      return { exitCode: 0, stdout: '', stderr: '' };
    });

    await restoreConsumer(deps, { consumer: ADMIN });

    expect(await fs.exists(`${ADMIN}/package-lock.json`)).toBe(false);
  });

  it('restores npm-shrinkwrap.json as well as package-lock.json', async () => {
    const files = { ...scenarioFiles(), [`${SHOP}/npm-shrinkwrap.json`]: json({ shrinkwrap: 'original' }) };
    const scenario = createScenario({ files, state: registered });
    await linkConsumer(scenario.deps, { library: '@acme/ui', consumer: SHOP });
    await syncLibrary(scenario.deps, { library: '@acme/ui' });
    await scenario.fs.writeText(`${SHOP}/npm-shrinkwrap.json`, json({ shrinkwrap: 'edited by npm' }));

    await restoreConsumer(scenario.deps, { consumer: SHOP });

    expect(await scenario.fs.readText(`${SHOP}/npm-shrinkwrap.json`)).toBe(
      files[`${SHOP}/npm-shrinkwrap.json`],
    );
  });

  it('finishes cleaning up and reports the error when npm cannot even start', async () => {
    const { deps, fs, process, store, events } = await linkedAndSynced([SHOP]);
    await fs.writeText(`${SHOP}/.angular/cache/stale.js`, 'dev build');
    const cannotStart = () => {
      throw new Error('spawn npm ENOENT');
    };
    process.on('npm install --no-audit', cannotStart);
    process.on('npm ci', cannotStart);

    const result = await restoreConsumer(deps, { consumer: SHOP });

    expect(result).toEqual({ ok: false, output: 'spawn npm ENOENT' });
    expect(await fs.exists(`${SHOP}/.angular/cache`)).toBe(false);
    expect(store.current.links).toEqual([]);
    expect(events.events.at(-1)).toEqual({ type: 'consumer:restored', consumer: SHOP, ok: false });
  });

  it('does not mistake a dependency field npm created for the library as a user change', async () => {
    const PLUGIN = '/repos/plugin';
    const pluginManifest = json({ name: 'plugin', peerDependencies: { '@acme/ui': '^1.4.0' } });
    const files = {
      ...scenarioFiles(),
      [`${PLUGIN}/package.json`]: pluginManifest,
      [`${PLUGIN}/package-lock.json`]: lockfileFor('plugin', {}),
    };
    const scenario = createScenario({ files, state: registered });
    await linkConsumer(scenario.deps, { library: '@acme/ui', consumer: PLUGIN });
    await syncLibrary(scenario.deps, { library: '@acme/ui' });
    const linked = JSON.parse((await scenario.fs.readText(`${PLUGIN}/package.json`)) ?? '');
    linked.devDependencies = { '@acme/ui': '1.4.1-dev.20261118143201' };
    await scenario.fs.writeText(`${PLUGIN}/package.json`, json(linked));

    await expect(restoreConsumer(scenario.deps, { consumer: PLUGIN })).resolves.toEqual({ ok: true });
    expect(await scenario.fs.readText(`${PLUGIN}/package.json`)).toBe(pluginManifest);
  });

  it('forgets the links and the snapshot afterwards', async () => {
    const { deps, fs, store } = await linkedAndSynced([SHOP, ADMIN]);

    await restoreConsumer(deps, { consumer: SHOP });

    expect(store.current.links.map((link) => link.consumer)).toEqual([ADMIN]);
    expect(await fs.exists(`${HOME}/snapshots/${pathSlug(SHOP)}`)).toBe(false);
  });

  it('clears framework caches so the dev server stops serving the dev build', async () => {
    const { deps, fs } = await linkedAndSynced([SHOP]);
    await fs.writeText(`${SHOP}/.angular/cache/20.1.3/vite/deps/acme-ui.js`, 'dev build');

    await restoreConsumer(deps, { consumer: SHOP });

    expect(await fs.exists(`${SHOP}/.angular/cache`)).toBe(false);
  });

  it('refuses to overwrite dependency changes the user made while linked', async () => {
    const { deps, fs } = await linkedAndSynced([SHOP]);
    const current = JSON.parse((await fs.readText(`${SHOP}/package.json`)) ?? '');
    current.dependencies.rxjs = '^8.0.0';
    await fs.writeText(`${SHOP}/package.json`, json(current));

    await expect(restoreConsumer(deps, { consumer: SHOP })).rejects.toMatchObject({
      code: 'manifest-drifted',
    });
    expect(JSON.parse((await fs.readText(`${SHOP}/package.json`)) ?? '').dependencies.rxjs).toBe('^8.0.0');
  });

  it('overwrites those changes when forced', async () => {
    const { deps, fs } = await linkedAndSynced([SHOP]);
    await fs.writeText(`${SHOP}/package.json`, json({ ...shopManifest, scripts: { start: 'ng serve' } }));

    await restoreConsumer(deps, { consumer: SHOP, force: true });

    expect(JSON.parse((await fs.readText(`${SHOP}/package.json`)) ?? '')).toEqual(shopManifest);
  });

  it('does not count dryfit’s own reordering of dependencies as a user change', async () => {
    const { deps, fs } = await linkedAndSynced([SHOP]);
    const current = JSON.parse((await fs.readText(`${SHOP}/package.json`)) ?? '');
    const reordered = {
      ...current,
      dependencies: Object.fromEntries(Object.entries(current.dependencies).reverse()),
    };
    await fs.writeText(`${SHOP}/package.json`, json(reordered));

    await expect(restoreConsumer(deps, { consumer: SHOP })).resolves.toEqual({ ok: true });
  });

  it('still restores the files when the clean install fails, and reports it', async () => {
    const original = createScenario().fs.snapshot(SHOP);
    const { deps, fs, process, store, events } = await linkedAndSynced([SHOP]);
    process.on('npm install --no-audit', failed('npm error network ETIMEDOUT'));
    process.on('npm ci', failed('npm error network ETIMEDOUT'));

    const result = await restoreConsumer(deps, { consumer: SHOP });

    expect(result).toEqual({ ok: false, output: 'npm error network ETIMEDOUT' });
    expect(manifestAndLock(fs.snapshot(SHOP), SHOP)).toEqual(manifestAndLock(original, SHOP));
    expect(store.current.links).toEqual([]);
    expect(events.events.at(-1)).toEqual({ type: 'consumer:restored', consumer: SHOP, ok: false });
  });

  it('rejects a consumer that was never linked', async () => {
    const { deps } = createScenario({ state: registered });

    await expect(restoreConsumer(deps, { consumer: SHOP })).rejects.toMatchObject({
      code: 'snapshot-missing',
    });
  });

  describe('one library of several', () => {
    const FORMS = '/repos/forms';
    const twoLibraries: DryfitState = {
      ...registered,
      libraries: [...registered.libraries, { name: '@acme/forms', root: FORMS, publishDir: FORMS }],
    };
    const files = () => ({
      ...scenarioFiles(),
      [`${FORMS}/package.json`]: json({ name: '@acme/forms', version: '2.0.0' }),
      [`${SHOP}/package.json`]: json({
        ...shopManifest,
        dependencies: { ...shopManifest.dependencies, '@acme/forms': '^2.0.0' },
      }),
      [`${SHOP}/package-lock.json`]: lockfileFor('shop', {
        '@acme/ui': '1.4.0',
        '@angular/core': '20.1.3',
        '@acme/forms': '2.0.0',
      }),
    });

    async function bothLinked() {
      const scenario = createScenario({ files: files(), state: twoLibraries });
      for (const library of ['@acme/ui', '@acme/forms']) {
        await linkConsumer(scenario.deps, { library, consumer: SHOP });
        await syncLibrary(scenario.deps, { library });
      }
      return scenario;
    }

    it('puts that library back on its release and keeps the others on their dev builds', async () => {
      const { deps, fs, store, events } = await bothLinked();
      const forms = store.current.links.find((link) => link.library === '@acme/forms');
      expect(forms?.installedVersion).toMatch(/^2\.0\.1-dev\./);

      const result = await restoreConsumer(deps, { consumer: SHOP, library: '@acme/ui' });

      expect(result).toEqual({ ok: true, libraries: ['@acme/ui'] });
      const manifest = JSON.parse((await fs.readText(`${SHOP}/package.json`)) ?? '{}');
      expect(manifest.dependencies['@acme/ui']).toBe('^1.4.0');
      expect(manifest.dependencies['@acme/forms']).toBe(forms?.installedVersion);
      const lock = JSON.parse((await fs.readText(`${SHOP}/package-lock.json`)) ?? '{}');
      expect(lock.packages['node_modules/@acme/ui'].version).toBe('1.4.0');
      expect(store.current.links).toEqual([
        expect.objectContaining({
          library: '@acme/forms',
          consumer: SHOP,
          status: 'installed',
          installedVersion: forms?.installedVersion,
        }),
      ]);
      expect(await fs.exists(`${HOME}/snapshots/${pathSlug(SHOP)}/meta.json`)).toBe(true);
      expect(events.events.at(-1)).toEqual({
        type: 'consumer:restored',
        consumer: SHOP,
        library: '@acme/ui',
        ok: true,
      });
    });

    it('restores the whole app, byte for byte, when the last library goes back', async () => {
      const original = createScenario({ files: files() }).fs.snapshot(SHOP);
      const { deps, fs, store } = await bothLinked();

      await restoreConsumer(deps, { consumer: SHOP, library: '@acme/ui' });
      await restoreConsumer(deps, { consumer: SHOP, library: '@acme/forms' });

      expect(manifestAndLock(fs.snapshot(SHOP), SHOP)).toEqual(manifestAndLock(original, SHOP));
      expect(store.current.links).toEqual([]);
      expect(await fs.exists(`${HOME}/snapshots/${pathSlug(SHOP)}`)).toBe(false);
    });

    it('leaves the others pending, for the next sync, when the clean install fails', async () => {
      const { deps, process, store } = await bothLinked();
      process.on('npm install --no-audit', async () => failed('npm error network'));
      process.on('npm ci', async () => failed('npm error network'));

      const result = await restoreConsumer(deps, { consumer: SHOP, library: '@acme/ui' });

      expect(result).toEqual({ ok: false, output: 'npm error network', libraries: ['@acme/ui'] });
      expect(store.current.links).toEqual([{ library: '@acme/forms', consumer: SHOP, status: 'pending' }]);
    });

    it('refuses a library that is not linked into the app', async () => {
      const { deps } = await linkedAndSynced([SHOP]);
      await expect(restoreConsumer(deps, { consumer: SHOP, library: '@acme/forms' })).rejects.toMatchObject({
        code: 'invalid-request',
      });
    });
  });
});
