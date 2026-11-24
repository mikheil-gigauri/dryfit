import { describe, expect, it } from 'vitest';
import { failed, ok } from '../../testing/fakes.ts';
import { ADMIN, BLOG, createScenario, HOME, json, LIB, SHOP, scenarioFiles } from '../../testing/scenario.ts';
import type { DryfitState } from '../model.ts';
import { pathSlug } from '../util/path.ts';
import { linkConsumer } from './link-consumer.ts';

const library = { name: '@acme/ui', root: LIB, publishDir: `${LIB}/dist/ui` };
const registered: DryfitState = { libraries: [library], links: [], groups: [] };
const published: DryfitState = {
  libraries: [{ ...library, lastPublishedVersion: '1.4.1-dev.20261118143201' }],
  links: [],
  groups: [],
};
const snapshotDir = (consumer: string) => `${HOME}/snapshots/${pathSlug(consumer)}`;

describe('linkConsumer', () => {
  it('snapshots the manifest, lockfile and dev server config before anything changes', async () => {
    const { deps, fs } = createScenario({ state: registered });
    const before = fs.snapshot(SHOP);

    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    const dir = snapshotDir(SHOP);
    expect(await fs.readText(`${dir}/package.json`)).toBe(before[`${SHOP}/package.json`]);
    expect(await fs.readText(`${dir}/package-lock.json`)).toBe(before[`${SHOP}/package-lock.json`]);
    expect(await fs.readText(`${dir}/configs/angular.json`)).toBe(before[`${SHOP}/angular.json`]);
    expect(JSON.parse((await fs.readText(`${dir}/meta.json`)) ?? '')).toEqual({
      consumer: SHOP,
      packageManager: 'npm',
      lockfiles: ['package-lock.json'],
      createdAt: '2026-11-18T14:32:01.000Z',
      configFiles: ['angular.json'],
    });
  });

  it('publishes a library that was never published, then installs it, so linking changes the app', async () => {
    const { deps, store, fs, process } = createScenario({ state: registered });

    const link = await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    const version = store.current.libraries[0]?.lastPublishedVersion;
    expect(version).toBe('1.4.1-dev.20261118143201');
    expect(process.lines().filter((line) => line.includes('npm publish'))).toHaveLength(1);
    expect(process.lines(SHOP)).toEqual([
      `npm install @acme/ui@${version} --save-exact --@acme:registry=http://127.0.0.1:4873/ --no-audit --no-fund`,
    ]);
    expect(link).toEqual({
      library: '@acme/ui',
      consumer: SHOP,
      status: 'installed',
      installedVersion: version,
    });
    expect(JSON.parse((await fs.readText(`${SHOP}/package.json`)) ?? '').dependencies['@acme/ui']).toBe(
      version,
    );
  });

  it('fails with the build output and leaves the link pending when the first build fails', async () => {
    const build = { command: 'npm', args: ['run', 'build'], cwd: LIB };
    const { deps, store, process } = createScenario({
      state: { ...registered, libraries: [{ ...library, build }] },
    });
    process.on('npm run build', failed('src/button.ts:3:7 - error TS2322'));

    await expect(linkConsumer(deps, { library: '@acme/ui', consumer: SHOP })).rejects.toMatchObject({
      code: 'build-failed',
      details: { library: '@acme/ui', output: expect.stringContaining('TS2322') },
    });
    expect(store.current.links).toEqual([{ library: '@acme/ui', consumer: SHOP, status: 'pending' }]);
    expect(process.lines(SHOP)).toEqual([]);
  });

  it('builds, publishes and installs again when a link left pending by a failed build is linked again', async () => {
    const build = { command: 'npm', args: ['run', 'build'], cwd: LIB };
    const { deps, store, process } = createScenario({
      state: { ...registered, libraries: [{ ...library, build }] },
    });
    process.on('npm run build', failed('error TS2322'));
    await expect(linkConsumer(deps, { library: '@acme/ui', consumer: SHOP })).rejects.toMatchObject({
      code: 'build-failed',
    });

    process.on('npm run build', ok());
    const link = await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    expect(link.status).toBe('installed');
    expect(store.current.links).toEqual([link]);
    expect(process.lines(SHOP)).toHaveLength(1);
  });

  it('refuses a workspace package without its own lockfile, whose install would change the root lockfile', async () => {
    const member = '/repos/mono/packages/widget';
    const { deps, store } = createScenario({
      state: published,
      files: {
        ...scenarioFiles(),
        '/repos/mono/package.json': json({ name: 'mono', workspaces: ['packages/*'] }),
        '/repos/mono/package-lock.json': json({ lockfileVersion: 3 }),
        [`${member}/package.json`]: json({ name: 'widget', dependencies: { '@acme/ui': '^1.4.0' } }),
      },
    });

    await expect(linkConsumer(deps, { library: '@acme/ui', consumer: member })).rejects.toMatchObject({
      code: 'not-a-consumer',
      details: { workspace: '/repos/mono' },
    });
    expect(store.current.links).toEqual([]);
  });

  it('refuses to snapshot an app whose files already hold a dryfit dev build', async () => {
    const { deps, fs, store } = createScenario({ state: published });
    const manifest = JSON.parse((await fs.readText(`${SHOP}/package.json`)) ?? '');
    manifest.dependencies['@acme/ui'] = '1.4.1-dev.20261118120000';
    await fs.writeText(`${SHOP}/package.json`, json(manifest));

    await expect(linkConsumer(deps, { library: '@acme/ui', consumer: SHOP })).rejects.toMatchObject({
      code: 'consumer-linked',
    });
    expect(store.current.links).toEqual([]);
    expect(await fs.readText(`${snapshotDir(SHOP)}/meta.json`)).toBeUndefined();
  });

  it('installs the latest dev version straight away when there is one', async () => {
    const { deps, process } = createScenario({ state: published });

    const link = await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    expect(process.lines(SHOP)).toEqual([
      'npm install @acme/ui@1.4.1-dev.20261118143201 --save-exact --@acme:registry=http://127.0.0.1:4873/ --no-audit --no-fund',
    ]);
    expect(link).toEqual({
      library: '@acme/ui',
      consumer: SHOP,
      status: 'installed',
      installedVersion: '1.4.1-dev.20261118143201',
    });
  });

  it('keeps the link but marks it failed, with the reason, when the first install fails', async () => {
    const { deps, npm, store } = createScenario({ state: published });
    npm.failIn(SHOP);

    const link = await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    expect(link).toEqual({
      library: '@acme/ui',
      consumer: SHOP,
      status: 'failed',
      message: 'npm error ERESOLVE could not resolve',
    });
    expect(store.current.links).toEqual([link]);
  });

  it('installs again, without a new snapshot, when a failed link is linked again', async () => {
    const { deps, npm, store, fs, process } = createScenario({ state: published });
    npm.failIn(SHOP);
    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });
    const snapshot = await fs.readText(`${snapshotDir(SHOP)}/package.json`);
    const failedManifest = JSON.parse(snapshot ?? '');

    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    expect(process.lines(SHOP)).toHaveLength(2);
    expect(store.current.links).toHaveLength(1);
    expect(JSON.parse((await fs.readText(`${snapshotDir(SHOP)}/package.json`)) ?? '')).toEqual(
      failedManifest,
    );
  });

  it('records a consumer without a lockfile so restore can remove the one npm creates', async () => {
    const { deps, fs } = createScenario({ state: registered });

    await linkConsumer(deps, { library: '@acme/ui', consumer: ADMIN });

    const meta = JSON.parse((await fs.readText(`${snapshotDir(ADMIN)}/meta.json`)) ?? '');
    expect(meta.lockfiles).toEqual([]);
    expect(await fs.exists(`${snapshotDir(ADMIN)}/package-lock.json`)).toBe(false);
  });

  it('keeps the first snapshot when a second library is linked into the same consumer', async () => {
    const second = { name: '@acme/icons', root: '/repos/icons', publishDir: '/repos/icons' };
    const files = {
      ...scenarioFiles(),
      [`${SHOP}/package.json`]: json({
        name: 'shop',
        dependencies: { '@acme/ui': '^1.4.0', '@acme/icons': '^2.0.0' },
      }),
      '/repos/icons/package.json': json({ name: '@acme/icons', version: '2.0.0' }),
    };
    const { deps, fs } = createScenario({
      files,
      state: { libraries: [library, second], links: [], groups: [] },
    });

    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });
    const original = await fs.readText(`${snapshotDir(SHOP)}/package.json`);
    await fs.writeText(
      `${SHOP}/package.json`,
      json({ name: 'shop', dependencies: { '@acme/ui': '1.4.1-dev.1', '@acme/icons': '^2.0.0' } }),
    );
    await linkConsumer(deps, { library: '@acme/icons', consumer: SHOP });

    expect(await fs.readText(`${snapshotDir(SHOP)}/package.json`)).toBe(original);
  });

  it('is idempotent', async () => {
    const { deps, store } = createScenario({ state: registered });

    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });
    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    expect(store.current.links).toHaveLength(1);
  });

  it('rejects an unknown library', async () => {
    const { deps } = createScenario({ state: registered });

    await expect(linkConsumer(deps, { library: '@acme/nope', consumer: SHOP })).rejects.toMatchObject({
      code: 'library-not-found',
    });
  });

  it('rejects a project that does not depend on the library', async () => {
    const { deps, fs } = createScenario({ state: registered });

    await expect(linkConsumer(deps, { library: '@acme/ui', consumer: BLOG })).rejects.toMatchObject({
      code: 'not-a-consumer',
    });
    expect(await fs.exists(snapshotDir(BLOG))).toBe(false);
  });

  it('refuses to guess between lockfiles from different package managers', async () => {
    const { deps } = createScenario({
      state: registered,
      files: { ...scenarioFiles(), [`${SHOP}/yarn.lock`]: '' },
    });

    await expect(linkConsumer(deps, { library: '@acme/ui', consumer: SHOP })).rejects.toMatchObject({
      code: 'package-manager-undetected',
    });
  });

  it('snapshots every lockfile npm may use, including npm-shrinkwrap.json', async () => {
    const files = { ...scenarioFiles(), [`${SHOP}/npm-shrinkwrap.json`]: json({ shrinkwrap: true }) };
    const { deps, fs } = createScenario({ files, state: registered });

    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    const meta = JSON.parse((await fs.readText(`${snapshotDir(SHOP)}/meta.json`)) ?? '');
    expect(meta.lockfiles).toEqual(['package-lock.json', 'npm-shrinkwrap.json']);
    expect(await fs.readText(`${snapshotDir(SHOP)}/npm-shrinkwrap.json`)).toBe(json({ shrinkwrap: true }));
  });

  it('treats differently spelled paths to the same consumer as one', async () => {
    const { deps, fs, store } = createScenario({ state: registered });

    await linkConsumer(deps, { library: '@acme/ui', consumer: `${SHOP}/` });
    await linkConsumer(deps, { library: '@acme/ui', consumer: `${SHOP}/./src/..` });

    expect(store.current.links.map((link) => [link.consumer, link.status])).toEqual([[SHOP, 'installed']]);
    expect((await fs.readDir(`${HOME}/snapshots`)).map((entry) => entry.name)).toEqual([
      pathSlug(SHOP).toString(),
    ]);
  });

  it('replaces a leftover snapshot that no link refers to, since it predates the current files', async () => {
    const files = {
      ...scenarioFiles(),
      [`${snapshotDir(SHOP)}/package.json`]: json({ name: 'shop', dependencies: { '@acme/ui': '^0.9.0' } }),
      [`${snapshotDir(SHOP)}/meta.json`]: json({ consumer: SHOP, packageManager: 'npm', lockfiles: [] }),
    };
    const { deps, fs } = createScenario({ files, state: registered });

    await linkConsumer(deps, { library: '@acme/ui', consumer: SHOP });

    expect(await fs.readText(`${snapshotDir(SHOP)}/package.json`)).toBe(files[`${SHOP}/package.json`]);
  });

  it('keeps state changes that land while the snapshot is being written', async () => {
    const { deps, store } = createScenario({ state: registered });
    const icons = { name: '@acme/icons', root: '/repos/icons', publishDir: '/repos/icons' };
    let interleaved = false;
    const fs = {
      ...deps.fs,
      readText: deps.fs.readText.bind(deps.fs),
      exists: deps.fs.exists.bind(deps.fs),
      readDir: deps.fs.readDir.bind(deps.fs),
      remove: deps.fs.remove.bind(deps.fs),
      copyDir: deps.fs.copyDir.bind(deps.fs),
      async writeText(path: string, content: string) {
        if (!interleaved && path.includes('/snapshots/')) {
          interleaved = true;
          await store.save({ ...store.current, libraries: [...store.current.libraries, icons] });
        }
        return deps.fs.writeText(path, content);
      },
    };

    await linkConsumer({ ...deps, fs }, { library: '@acme/ui', consumer: SHOP });

    expect(store.current.libraries.map((entry) => entry.name).sort()).toEqual(['@acme/icons', '@acme/ui']);
  });

  it('rejects a package manager it has no adapter for yet', async () => {
    const { [`${SHOP}/package-lock.json`]: _npmLockfile, ...files } = scenarioFiles();
    const { deps } = createScenario({
      state: registered,
      files: { ...files, [`${SHOP}/pnpm-lock.yaml`]: '' },
    });

    await expect(linkConsumer(deps, { library: '@acme/ui', consumer: SHOP })).rejects.toMatchObject({
      code: 'unsupported-package-manager',
    });
  });
});
