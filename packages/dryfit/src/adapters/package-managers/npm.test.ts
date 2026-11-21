import { describe, expect, it } from 'vitest';
import { installSpec } from '../../testing/install-spec.ts';
import { npm, npmPublisher } from './npm.ts';

const registryUrl = 'http://127.0.0.1:4873/';

describe('npm adapter', () => {
  describe('install', () => {
    it('pins the exact version and points only the package scope at the local registry', () => {
      expect(npm.install(installSpec(['@acme/ui']))).toEqual({
        command: 'npm',
        args: [
          'install',
          '@acme/ui@1.4.1-dev.20261118143201',
          '--save-exact',
          '--@acme:registry=http://127.0.0.1:4873/',
          '--no-audit',
          '--no-fund',
        ],
        cwd: '/apps/shop',
      });
    });

    it('uses the local registry for everything when the package is unscoped', () => {
      expect(npm.install(installSpec(['ui-kit'])).args).toContain('--registry=http://127.0.0.1:4873/');
    });

    it.each([
      ['dependencies', undefined],
      ['devDependencies', '--save-dev'],
      ['optionalDependencies', '--save-optional'],
      ['peerDependencies', '--save-peer'],
    ] as const)('keeps a package declared in %s in that field', (dependencyField, flag) => {
      const args = npm.install(installSpec([['@acme/ui', dependencyField]])).args;
      const saveFlags = args.filter((arg) => /^--save-(dev|optional|peer)$/.test(arg));

      expect(saveFlags).toEqual(flag === undefined ? [] : [flag]);
    });

    it('installs several dev builds in one run, one registry setting per scope', () => {
      expect(npm.install(installSpec(['@acme/common', '@acme/ui', '@tools/lint'])).args).toEqual([
        'install',
        '@acme/common@1.4.1-dev.20261118143201',
        '@acme/ui@1.4.1-dev.20261118143201',
        '@tools/lint@1.4.1-dev.20261118143201',
        '--save-exact',
        '--@acme:registry=http://127.0.0.1:4873/',
        '--@tools:registry=http://127.0.0.1:4873/',
        '--no-audit',
        '--no-fund',
      ]);
    });

    it('passes no save flag when the packages sit in different fields, so npm keeps each where it is', () => {
      const args = npm.install(
        installSpec([
          ['@acme/common', 'dependencies'],
          ['@acme/ui', 'devDependencies'],
        ]),
      ).args;

      expect(args.filter((arg) => arg.startsWith('--save-'))).toEqual(['--save-exact']);
    });

    it('keeps a shared field when every package sits in it', () => {
      const args = npm.install(
        installSpec([
          ['@acme/common', 'devDependencies'],
          ['@acme/ui', 'devDependencies'],
        ]),
      ).args;

      expect(args).toContain('--save-dev');
    });

    it('uses the local registry for everything when any package is unscoped', () => {
      const args = npm.install(installSpec(['@acme/ui', 'ui-kit'])).args;

      expect(args.filter((arg) => arg.includes('registry='))).toEqual(['--registry=http://127.0.0.1:4873/']);
    });
  });

  describe('cleanInstall', () => {
    it('installs exactly from the lockfile when there is one', () => {
      expect(npm.cleanInstall({ cwd: '/apps/shop', hasLockfile: true })).toEqual({
        command: 'npm',
        args: ['ci', '--no-audit', '--no-fund'],
        cwd: '/apps/shop',
      });
    });

    it('installs only what differs from the lockfile when node_modules may be reused', () => {
      expect(npm.cleanInstall({ cwd: '/apps/shop', hasLockfile: true, incremental: true }).args).toEqual([
        'install',
        '--no-audit',
        '--no-fund',
      ]);
    });

    it('never creates a lockfile, even when node_modules may be reused', () => {
      expect(npm.cleanInstall({ cwd: '/apps/shop', hasLockfile: false, incremental: true }).args).toEqual([
        'install',
        '--no-package-lock',
        '--no-audit',
        '--no-fund',
      ]);
    });

    it('falls back to a plain install when there is no lockfile', () => {
      expect(npm.cleanInstall({ cwd: '/apps/shop', hasLockfile: false }).args).toEqual([
        'install',
        '--no-package-lock',
        '--no-audit',
        '--no-fund',
      ]);
    });
  });

  describe('publish', () => {
    it('publishes to the local registry under the given dist-tag, never with provenance or lifecycle scripts', () => {
      expect(
        npmPublisher.publish({ cwd: '/staging/ui', packageName: 'ui', registryUrl, tag: 'dryfit' }),
      ).toEqual({
        command: 'npm',
        args: [
          'publish',
          '--ignore-scripts',
          '--registry=http://127.0.0.1:4873/',
          '--tag=dryfit',
          '--provenance=false',
        ],
        cwd: '/staging/ui',
      });
    });

    it("pins a scoped package's scope to the local registry, which beats the user's @scope:registry", () => {
      expect(
        npmPublisher.publish({ cwd: '/staging/ui', packageName: '@acme/ui', registryUrl, tag: 'dryfit' })
          .args,
      ).toEqual([
        'publish',
        '--ignore-scripts',
        '--registry=http://127.0.0.1:4873/',
        '--@acme:registry=http://127.0.0.1:4873/',
        '--tag=dryfit',
        '--provenance=false',
      ]);
    });

    const credentials = { username: 'dryfit', password: 's3cret' };

    it('authenticates through an .npmrc in the staging folder, keeping credentials out of the process list', () => {
      // base64('dryfit:s3cret'): npm sends it as HTTP Basic auth.
      expect(npmPublisher.publishAuthFiles({ registryUrl, credentials })).toEqual({
        '.npmrc': '//127.0.0.1:4873/:_auth=ZHJ5Zml0OnMzY3JldA==\n',
      });
    });

    it('scopes the credentials to the registry host and path', () => {
      expect(
        npmPublisher.publishAuthFiles({ registryUrl: 'http://127.0.0.1:4873/sub', credentials }),
      ).toEqual({
        '.npmrc': '//127.0.0.1:4873/sub/:_auth=ZHJ5Zml0OnMzY3JldA==\n',
      });
    });
  });
});
