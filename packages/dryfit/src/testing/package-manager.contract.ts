import { readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { npm, npmPublisher } from '../adapters/package-managers/npm.ts';
import { DEV_VERSION_PATTERN } from '../core/guard/commit-guard.ts';
import type { InstallPackage, PackageManagerAdapter, Publisher, RunSpec } from '../core/ports.ts';
import { createRegistrySandbox, distTags, type RegistrySandbox } from './registry-sandbox.ts';

const LIB = '@fixture/ui';
const RELEASE = '1.0.0';
const DEV = '1.0.1-dev.20261118143201';
const FORMS = '@fixture/forms';
/** A sibling from the same workspace that peers on the library exactly, release and dev build alike. */
const PINNED = '@fixture/pinned';
/** Nothing listens here: a consumer whose own registry for the scope is this can only get a dev build from dryfit. */
const DEAD_REGISTRY = 'http://127.0.0.1:1/';

/** How a developer using this package manager set up and installed their project. */
export interface ConsumerSetup {
  /** Writes the project's own registry config so `@fixture` packages come from `registryUrl`. */
  pointScopeAt(dir: string, registryUrl: string): Promise<void>;
  /** The install they ran in the project, before dryfit was ever involved. */
  readonly install: Omit<RunSpec, 'cwd'>;
}

/** Releases the fixtures: the library, a dev build of it, and a sibling that peers on the library. */
async function publishFixtures(sandbox: RegistrySandbox, publisher: Publisher) {
  const publish = async (
    version: string,
    tag: string,
    code: string,
    {
      name = LIB,
      manifest = {},
      env,
    }: { name?: string; manifest?: object; env?: Readonly<Record<string, string>> } = {},
  ) => {
    const dir = await sandbox.writePackage(
      join(sandbox.dir, `publish-${name.replace('/', '_')}-${version}`),
      { name, version, main: 'index.js', ...manifest },
      { 'index.js': `module.exports = ${code};\n` },
    );
    const { registry } = sandbox;
    for (const [file, content] of Object.entries(
      publisher.publishAuthFiles({ registryUrl: registry.url, credentials: registry.credentials }),
    )) {
      await writeFile(join(dir, file), content);
    }
    const spec = publisher.publish({ cwd: dir, packageName: name, registryUrl: registry.url, tag });
    await sandbox.run(spec.command, spec.args, spec.cwd, env);
  };
  return publish;
}

/**
 * What every package manager adapter must do against a real registry with the real tool (ADR 0006,
 * ADR 0009). "Supports pnpm" means this suite passes for the pnpm adapter.
 */
export function describePackageManagerContract(adapter: PackageManagerAdapter, setup: ConsumerSetup): void {
  describe(`PackageManagerAdapter contract: ${adapter.name}`, () => {
    let sandbox: RegistrySandbox;
    let consumerCount = 0;
    const lockfileName = adapter.lockfiles[0] ?? '';

    const exec = (spec: RunSpec) =>
      sandbox.runner.run(spec).then((result) => {
        if (result.exitCode !== 0) {
          throw new Error(
            `${spec.command} ${spec.args.join(' ')} failed:\n${result.stderr || result.stdout}`,
          );
        }
        return result;
      });

    /** A consumer that depends on the released library, installed the way its developer would have. */
    const createConsumer = async (
      field: 'dependencies' | 'devDependencies' = 'dependencies',
      otherDependencies: Readonly<Record<string, string>> = {},
      devDependencies?: Readonly<Record<string, string>>,
    ) => {
      const dir = await sandbox.writePackage(join(sandbox.dir, `consumer-${++consumerCount}`), {
        name: `consumer-${consumerCount}`,
        version: '0.0.0',
        private: true,
        [field]: { [LIB]: `^${RELEASE}`, ...otherDependencies },
        ...(devDependencies && { devDependencies }),
      });
      await setup.pointScopeAt(dir, sandbox.registry.url);
      await exec({ ...setup.install, cwd: dir });
      return dir;
    };

    /** Installs dev builds the way dryfit does, with the project's own registry for the scope unreachable. */
    const installDev = async (
      cwd: string,
      dependencyField: 'dependencies' | 'devDependencies' = 'dependencies',
      others: readonly InstallPackage[] = [],
    ) => {
      await setup.pointScopeAt(cwd, DEAD_REGISTRY);
      await exec(
        adapter.install({
          cwd,
          packages: [{ name: LIB, version: DEV, dependencyField }, ...others],
          registryUrl: sandbox.registry.url,
        }),
      );
      await setup.pointScopeAt(cwd, sandbox.registry.url);
    };

    const requireFrom = async (cwd: string, name: string) =>
      (await sandbox.run(process.execPath, ['-p', `require(${JSON.stringify(name)})`], cwd)).stdout.trim();

    const manifestOf = async (cwd: string) => JSON.parse(await readFile(join(cwd, 'package.json'), 'utf8'));

    /** The files directly in a folder, with their contents; folders such as node_modules are left out. */
    const rootFiles = async (dir: string) => {
      const entries = await readdir(dir, { withFileTypes: true });
      const files = entries.filter((entry) => entry.isFile()).map((entry) => entry.name);
      return Object.fromEntries(
        await Promise.all(
          files.map(async (file) => [file, await readFile(join(dir, file), 'utf8')] as const),
        ),
      );
    };

    beforeAll(async () => {
      sandbox = await createRegistrySandbox();
      const publish = await publishFixtures(sandbox, npmPublisher);
      await publish(RELEASE, 'latest', JSON.stringify('release'));
      await publish(DEV, 'dryfit', JSON.stringify('dev build'));
      // A sibling package that peers on the library, re-exporting whichever copy it resolves.
      await publish(RELEASE, 'latest', `require(${JSON.stringify(LIB)})`, {
        name: FORMS,
        manifest: { peerDependencies: { [LIB]: `^${RELEASE}` } },
      });
      // Pinned exactly, as Nx release writes it; dryfit pins the dev build to the library's (ADR 0014).
      await publish(RELEASE, 'latest', `require(${JSON.stringify(LIB)})`, {
        name: PINNED,
        manifest: { peerDependencies: { [LIB]: RELEASE } },
      });
      await publish(DEV, 'dryfit', `require(${JSON.stringify(LIB)})`, {
        name: PINNED,
        manifest: { peerDependencies: { [LIB]: DEV } },
      });
    }, 60_000);
    afterAll(() => sandbox?.dispose());

    it('installs the dev build past the project’s own registry, and the consumer runs its code', async () => {
      const consumer = await createConsumer();

      await installDev(consumer);

      expect((await manifestOf(consumer)).dependencies[LIB]).toContain(DEV);
      expect(await requireFrom(consumer, LIB)).toBe('dev build');
    });

    it('keeps the package in devDependencies when it was declared there', async () => {
      const consumer = await createConsumer('devDependencies');

      await installDev(consumer, 'devDependencies');

      const manifest = await manifestOf(consumer);
      expect(manifest.devDependencies[LIB]).toContain(DEV);
      expect(manifest.dependencies).toBeUndefined();
    });

    it('changes nothing in the project but its manifest and lockfile', async () => {
      const consumer = await createConsumer();
      const before = await rootFiles(consumer);

      await installDev(consumer);

      const after = await rootFiles(consumer);
      for (const file of ['package.json', ...adapter.lockfiles]) {
        delete before[file];
        delete after[file];
      }
      expect(after).toEqual(before);
    });

    it('leaves the dev build in the lockfile where the commit guard finds it, and nothing once restored', async () => {
      const consumer = await createConsumer();
      const original = await readFile(join(consumer, lockfileName), 'utf8');

      await installDev(consumer);

      const guard = new RegExp(DEV_VERSION_PATTERN);
      expect(await readFile(join(consumer, lockfileName), 'utf8')).toMatch(guard);
      expect(original).not.toMatch(guard);
    });

    it('reinstalls exactly what a restored lockfile says', async () => {
      const consumer = await createConsumer();
      const manifest = await readFile(join(consumer, 'package.json'), 'utf8');
      const lockfile = await readFile(join(consumer, lockfileName), 'utf8');
      await installDev(consumer);

      await writeFile(join(consumer, 'package.json'), manifest);
      await writeFile(join(consumer, lockfileName), lockfile);
      await exec(adapter.cleanInstall({ cwd: consumer, hasLockfile: true }));

      expect(await requireFrom(consumer, LIB)).toBe('release');
      expect(await readFile(join(consumer, lockfileName), 'utf8')).toBe(lockfile);
    });

    it('reinstalls what a restored lockfile says without deleting node_modules first', async () => {
      const consumer = await createConsumer();
      const manifest = await readFile(join(consumer, 'package.json'), 'utf8');
      const lockfile = await readFile(join(consumer, lockfileName), 'utf8');
      await installDev(consumer);

      await writeFile(join(consumer, 'package.json'), manifest);
      await writeFile(join(consumer, lockfileName), lockfile);
      await exec(adapter.cleanInstall({ cwd: consumer, hasLockfile: true, incremental: true }));

      expect(await requireFrom(consumer, LIB)).toBe('release');
      expect(await readFile(join(consumer, lockfileName), 'utf8')).toBe(lockfile);
    });

    it('installs a dev version even when another dependency peers on a release range', async () => {
      // A prerelease never satisfies `^1.0.0` (ADR 0004). The adapter must still install it, and the
      // dependent must resolve the single dev copy rather than a second, released one.
      const consumer = await createConsumer('dependencies', { [FORMS]: `^${RELEASE}` });

      await installDev(consumer);

      expect(await requireFrom(consumer, FORMS)).toBe('dev build');
      const manifest = await manifestOf(consumer);
      expect([manifest.overrides, manifest.resolutions, manifest.pnpm]).toEqual([
        undefined,
        undefined,
        undefined,
      ]);
    });

    it('installs dev builds that pin each other exactly in one run, each keeping its own field', async () => {
      // One at a time, either install conflicts with the other package's exact pin.
      const consumer = await createConsumer('dependencies', {}, { [PINNED]: RELEASE });

      await installDev(consumer, 'dependencies', [
        { name: PINNED, version: DEV, dependencyField: 'devDependencies' },
      ]);

      const after = await manifestOf(consumer);
      expect(after.dependencies[LIB]).toContain(DEV);
      expect(after.devDependencies[PINNED]).toContain(DEV);
      expect(after.dependencies[PINNED]).toBeUndefined();
      expect(await requireFrom(consumer, PINNED)).toBe('dev build');
    });

    it('installs from the manifest when there is no lockfile', async () => {
      const consumer = await createConsumer();
      for (const lockfile of adapter.lockfiles) await rm(join(consumer, lockfile), { force: true });
      await rm(join(consumer, 'node_modules'), { recursive: true, force: true });

      await exec(adapter.cleanInstall({ cwd: consumer, hasLockfile: false }));

      expect(await requireFrom(consumer, LIB)).toBe('release');
    });
  });
}

/**
 * What the publisher must do against a real registry: publish under the dev tag without moving
 * `latest`, and never put its credentials in the tarball.
 */
export function describePublisherContract(publisher: Publisher): void {
  describe('Publisher contract', () => {
    let sandbox: RegistrySandbox;
    let publish: Awaited<ReturnType<typeof publishFixtures>>;

    beforeAll(async () => {
      sandbox = await createRegistrySandbox();
      publish = await publishFixtures(sandbox, publisher);
      await publish(RELEASE, 'latest', JSON.stringify('release'));
      await publish(DEV, 'dryfit', JSON.stringify('dev build'));
    }, 60_000);
    afterAll(() => sandbox?.dispose());

    it('publishes under the dev tag, leaving latest on the release', async () => {
      expect(await distTags(sandbox.registry, LIB)).toEqual({ latest: RELEASE, dryfit: DEV });
    });

    it('never ships the credentials, even when the package lists them in `files`', async () => {
      const leaky = `${RELEASE}-leaky.0`;
      const authFiles = Object.keys(
        publisher.publishAuthFiles({
          registryUrl: sandbox.registry.url,
          credentials: sandbox.registry.credentials,
        }),
      );
      await publish(leaky, 'dryfit', '"leaky"', { manifest: { files: ['index.js', ...authFiles] } });
      const consumer = await sandbox.writePackage(join(sandbox.dir, 'consumer'), {
        name: 'consumer',
        private: true,
        dependencies: { [LIB]: leaky },
      });
      await writeFile(join(consumer, '.npmrc'), `@fixture:registry=${sandbox.registry.url}\n`);
      const spec = npm.cleanInstall({ cwd: consumer, hasLockfile: false });
      await sandbox.run(spec.command, spec.args, spec.cwd);

      const installed = join(consumer, 'node_modules', LIB);
      expect(await readFile(join(installed, 'index.js'), 'utf8')).toContain('leaky');
      for (const file of authFiles)
        await expect(readFile(join(installed, file), 'utf8')).rejects.toThrow(/ENOENT/);
    });

    it("publishes to the local registry even when the user's npmrc sends the scope elsewhere", async () => {
      // The usual setup for a private scope on npmjs.org, which would otherwise receive the dev build.
      const userconfig = join(sandbox.dir, 'scoped-user.npmrc');
      await writeFile(userconfig, `@fixture:registry=${DEAD_REGISTRY}\n`);
      const scoped = `${RELEASE}-scoped.0`;

      await publish(scoped, 'dryfit', '"scoped"', { env: { npm_config_userconfig: userconfig } });

      expect((await distTags(sandbox.registry, LIB)).dryfit).toBe(scoped);
    });
  });
}
