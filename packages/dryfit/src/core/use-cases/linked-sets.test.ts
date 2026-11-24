import { describe, expect, it } from 'vitest';
import { createScenario, HOME, json, lockfileFor } from '../../testing/scenario.ts';
import type { DryfitState, LibraryRecord } from '../model.ts';
import { linkConsumer, linkLibraries } from './link-consumer.ts';
import { restoreConsumer } from './restore-consumer.ts';
import { snapshotDir } from './shared.ts';
import { syncLibrary } from './sync-library.ts';

/**
 * An Nx workspace with independent releases (ADR 0014): `ui` peers on `common` exactly, `assets`
 * stands alone, and the app's released `ui` pins its released `common` exactly as well.
 */
const WS = '/repos/ws';
const APP = '/repos/app';
const lib = (name: string): LibraryRecord => ({
  name: `@ws/${name}`,
  root: `${WS}/libs/${name}`,
  publishDir: `${WS}/dist/libs/${name}`,
});
const [COMMON, UI, ASSETS] = ['@ws/common', '@ws/ui', '@ws/assets'] as const;

function workspace({
  links = [] as DryfitState['links'],
  published = {} as Record<string, string>,
  pinnedSiblings = {} as Record<string, Record<string, string>>,
  registered = ['common', 'ui', 'assets'],
  root = {} as Record<string, string>,
} = {}) {
  const libraries = registered.map((name) => {
    const record = lib(name);
    const version = published[record.name];
    const pinned = pinnedSiblings[record.name];
    return version === undefined
      ? record
      : { ...record, lastPublishedVersion: version, ...(pinned && { pinnedSiblings: pinned }) };
  });
  const files: Record<string, string> = {
    ...root,
    [`${WS}/libs/common/package.json`]: json({ name: COMMON, version: '19.24.0' }),
    [`${WS}/dist/libs/common/package.json`]: json({ name: COMMON, version: '19.24.0' }),
    [`${WS}/libs/ui/package.json`]: json({
      name: UI,
      version: '19.40.0',
      peerDependencies: { [COMMON]: '19.24.0' },
    }),
    [`${WS}/dist/libs/ui/package.json`]: json({
      name: UI,
      version: '19.40.0',
      peerDependencies: { [COMMON]: '19.24.0' },
    }),
    [`${WS}/libs/assets/package.json`]: json({ name: ASSETS, version: '19.10.0' }),
    [`${WS}/dist/libs/assets/package.json`]: json({ name: ASSETS, version: '19.10.0' }),
    [`${APP}/package.json`]: json({
      name: 'app',
      dependencies: { [COMMON]: '19.33.0', [UI]: '19.50.1', [ASSETS]: '19.12.0' },
    }),
    [`${APP}/package-lock.json`]: lockfileFor('app', {
      [COMMON]: '19.33.0',
      [UI]: '19.50.1',
      [ASSETS]: '19.12.0',
    }),
  };
  const scenario = createScenario({ files, state: { libraries, links, groups: [] } });
  // The app's released ui pins its released common, and ui's dev build pins common's dev build.
  scenario.npm.requireTogether(APP, [COMMON, UI]);
  const staged = new Map<string, Record<string, unknown>>();
  scenario.process.on('npm publish', async (spec) => {
    const manifest = JSON.parse((await scenario.fs.readText(`${spec.cwd}/package.json`)) ?? '{}');
    staged.set(manifest.name, manifest);
    return { exitCode: 0, stdout: '', stderr: '' };
  });
  return { ...scenario, staged };
}

const pending = (library: string) => ({ library, consumer: APP, status: 'pending' as const });
const versionOf = (state: DryfitState, name: string) =>
  state.libraries.find((library) => library.name === name)?.lastPublishedVersion;

describe('libraries that pin each other (ADR 0014)', () => {
  describe('sync', () => {
    it('publishes a library, then the linked ones depending on it, pinned to its new dev build', async () => {
      const { deps, store, staged } = workspace({ links: [pending(COMMON), pending(UI)] });

      const result = await syncLibrary(deps, { library: COMMON });

      const common = versionOf(store.current, COMMON);
      const ui = versionOf(store.current, UI);
      expect(result.published).toEqual([
        { library: COMMON, version: common },
        { library: UI, version: ui },
      ]);
      expect(staged.get(UI)?.peerDependencies).toEqual({ [COMMON]: common });
    });

    it('installs the whole linked set into the app in one run', async () => {
      const { deps, store, npm } = workspace({ links: [pending(COMMON), pending(UI)] });

      const result = await syncLibrary(deps, { library: COMMON });

      const common = versionOf(store.current, COMMON);
      const ui = versionOf(store.current, UI);
      expect(npm.installs).toEqual([[`${COMMON}@${common}`, `${UI}@${ui}`]]);
      expect(result.installs).toEqual([
        expect.objectContaining({
          consumer: APP,
          ok: true,
          version: common,
          libraries: [
            { library: COMMON, version: common },
            { library: UI, version: ui },
          ],
        }),
      ]);
      expect(store.current.links.map((link) => [link.library, link.status, link.installedVersion])).toEqual([
        [COMMON, 'installed', common],
        [UI, 'installed', ui],
      ]);
    });

    it('publishes a linked dependency that has no dev build yet before the library needing it', async () => {
      const { deps, store, staged } = workspace({ links: [pending(COMMON), pending(UI)] });

      const result = await syncLibrary(deps, { library: UI });

      expect(result.published.map((entry) => entry.library)).toEqual([COMMON, UI]);
      expect(result.version).toBe(versionOf(store.current, UI));
      expect(staged.get(UI)?.peerDependencies).toEqual({ [COMMON]: versionOf(store.current, COMMON) });
    });

    it('republishes only the library when nothing depends on it, but still installs the set together', async () => {
      const published = { [COMMON]: '19.24.1-dev.20261118100000', [UI]: '19.40.1-dev.20261118100001' };
      const { deps, npm } = workspace({ links: [pending(COMMON), pending(UI)], published });

      const result = await syncLibrary(deps, { library: UI });

      expect(result.published.map((entry) => entry.library)).toEqual([UI]);
      expect(npm.installs).toEqual([[`${UI}@${result.version}`, `${COMMON}@${published[COMMON]}`]]);
    });

    it('republishes a dependent with a dev build even where it is not linked, so its pins stay current', async () => {
      const { deps } = workspace({ published: { [UI]: '19.40.1-dev.20261118100001' } });

      const result = await syncLibrary(deps, { library: COMMON });

      expect(result.published.map((entry) => entry.library)).toEqual([COMMON, UI]);
    });

    it('leaves a dependent alone that has no dev build and is linked nowhere', async () => {
      const { deps } = workspace();

      const result = await syncLibrary(deps, { library: COMMON });

      expect(result.published.map((entry) => entry.library)).toEqual([COMMON]);
    });
  });

  describe('link', () => {
    const published = { [COMMON]: '19.24.1-dev.20261118100000', [UI]: '19.40.1-dev.20261118100001' };
    const pinnedSiblings = { [UI]: { [COMMON]: published[COMMON] } };

    it('links several libraries with one snapshot and installs them in one run', async () => {
      const { deps, npm, fs } = workspace({ published, pinnedSiblings });
      const lockfile = await fs.readText(`${APP}/package-lock.json`);

      const links = await linkLibraries(deps, { libraries: [COMMON, UI], consumer: APP });

      expect(links.map((link) => [link.library, link.status])).toEqual([
        [COMMON, 'installed'],
        [UI, 'installed'],
      ]);
      expect(npm.installs).toEqual([[`${COMMON}@${published[COMMON]}`, `${UI}@${published[UI]}`]]);
      expect(await fs.readText(`${snapshotDir({ home: HOME }, APP)}/package-lock.json`)).toBe(lockfile);
    });

    it.each([
      ['published before dryfit recorded its pins', {}],
      ['pinning an older dev build of its sibling', { [UI]: { [COMMON]: '19.24.1-dev.20261117090000' } }],
    ])('publishes a dev build again before installing when it was %s', async (_, pinnedSiblings) => {
      const { deps, npm, store, staged } = workspace({ published, pinnedSiblings });

      const links = await linkLibraries(deps, { libraries: [COMMON, UI], consumer: APP });

      const ui = versionOf(store.current, UI);
      expect(ui).not.toBe(published[UI]);
      expect(staged.get(UI)?.peerDependencies).toEqual({ [COMMON]: published[COMMON] });
      expect([...staged.keys()]).toEqual([UI]);
      expect(npm.installs).toEqual([[`${COMMON}@${published[COMMON]}`, `${UI}@${ui}`]]);
      expect(links.map((link) => [link.library, link.status])).toEqual([
        [COMMON, 'installed'],
        [UI, 'installed'],
      ]);
    });

    it('publishes libraries never published, dependencies first, then installs them together', async () => {
      const { deps, npm, store, staged } = workspace();

      const links = await linkLibraries(deps, { libraries: [UI, COMMON], consumer: APP });

      const common = versionOf(store.current, COMMON);
      const ui = versionOf(store.current, UI);
      expect([...staged.keys()]).toEqual([COMMON, UI]);
      expect(staged.get(UI)?.peerDependencies).toEqual({ [COMMON]: common });
      expect(npm.installs).toEqual([[`${UI}@${ui}`, `${COMMON}@${common}`]]);
      expect(links.map((link) => [link.library, link.status])).toEqual([
        [UI, 'installed'],
        [COMMON, 'installed'],
      ]);
    });

    it('records the sibling versions a dev build pinned, so the next link reuses it', async () => {
      const { deps, store, staged } = workspace({ published });

      await linkLibraries(deps, { libraries: [COMMON, UI], consumer: APP });
      staged.clear();
      await restoreConsumer(deps, { consumer: APP });
      await linkLibraries(deps, { libraries: [COMMON, UI], consumer: APP });

      const ui = store.current.libraries.find((library) => library.name === UI);
      expect(ui?.pinnedSiblings).toEqual({ [COMMON]: published[COMMON] });
      expect(staged.size).toBe(0);
    });

    it('installs both once the second is linked, after linking the first alone failed', async () => {
      const { deps, store } = workspace({ published });

      const first = await linkConsumer(deps, { library: COMMON, consumer: APP });
      const second = await linkConsumer(deps, { library: UI, consumer: APP });

      expect([first.status, second.status]).toEqual(['failed', 'installed']);
      expect(store.current.links.map((link) => [link.library, link.status])).toEqual([
        [COMMON, 'installed'],
        [UI, 'installed'],
      ]);
    });

    it('says which tied library to link along when installing alone fails', async () => {
      const { deps, events } = workspace({ published });

      await linkConsumer(deps, { library: COMMON, consumer: APP });

      const failure = events.events.find((event) => event.type === 'install:failed');
      expect(failure && 'output' in failure && failure.output).toContain(
        `${APP} also uses ${UI}, tied to ${COMMON} by their workspace's dependencies but not linked.`,
      );
      expect(failure && 'output' in failure && failure.output).toContain(
        `dryfit link ${APP} --library ${COMMON} --library ${UI}`,
      );
    });

    it.each([
      ['an npm workspace', { [`${WS}/package.json`]: json({ name: 'ws', workspaces: ['libs/*'] }) }],
      ['an Nx workspace', { [`${WS}/package.json`]: json({ name: 'ws' }), [`${WS}/nx.json`]: json({}) }],
    ])(
      'says to register and link a sibling the dev build pins when it is not registered, in %s',
      async (_, root) => {
        const { deps, events, store } = workspace({ published, registered: ['ui', 'assets'], root });

        const result = await linkConsumer(deps, { library: UI, consumer: APP });

        expect(result.status).toBe('failed');
        const failure = events.events.find((event) => event.type === 'install:failed');
        const output = failure && 'output' in failure ? failure.output : '';
        const saved = store.current.links.find((link) => link.library === UI)?.message;
        // The CLI prints the output; `dryfit status` and the menu bar app show the link's message.
        for (const text of [output, result.message, saved]) {
          expect(text).toContain('npm error ERESOLVE');
          expect(text).toContain(
            `${UI} depends on ${COMMON}, which ${APP} also uses, but dryfit does not know ${COMMON}.`,
          );
          expect(text).toContain(`dryfit add ${WS}/libs/common`);
          expect(text).toContain(`dryfit link ${APP} --library ${UI} --library ${COMMON}`);
        }
      },
    );

    it('refuses the whole set, touching nothing, when the app does not use one of them', async () => {
      const { deps, fs, store } = workspace({ published });
      await fs.writeText(`${APP}/package.json`, json({ name: 'app', dependencies: { [COMMON]: '19.33.0' } }));
      const before = fs.snapshot();

      await expect(linkLibraries(deps, { libraries: [COMMON, UI], consumer: APP })).rejects.toMatchObject({
        code: 'not-a-consumer',
        details: { library: UI },
      });
      expect(fs.snapshot()).toEqual(before);
      expect(store.current.links).toEqual([]);
    });
  });

  describe('restore', () => {
    async function allLinked() {
      const scenario = workspace({
        published: {
          [COMMON]: '19.24.1-dev.20261118100000',
          [UI]: '19.40.1-dev.20261118100001',
          [ASSETS]: '19.10.1-dev.20261118100002',
        },
      });
      const original = scenario.fs.snapshot(APP);
      await linkLibraries(scenario.deps, { libraries: [COMMON, UI, ASSETS], consumer: APP });
      return { ...scenario, original };
    }

    it('restores the libraries tied to the one asked for, and keeps the others', async () => {
      const { deps, store, npm } = await allLinked();

      const result = await restoreConsumer(deps, { consumer: APP, library: UI });

      expect(result).toEqual({ ok: true, libraries: [COMMON, UI] });
      expect(store.current.links.map((link) => [link.library, link.status])).toEqual([[ASSETS, 'installed']]);
      expect(npm.installs.at(-1)).toEqual([`${ASSETS}@19.10.1-dev.20261118100002`]);
    });

    it('puts the app back byte for byte', async () => {
      const { deps, fs, original } = await allLinked();

      expect(await restoreConsumer(deps, { consumer: APP })).toEqual({ ok: true });

      expect(fs.snapshot(APP)).toEqual(original);
    });
  });
});
