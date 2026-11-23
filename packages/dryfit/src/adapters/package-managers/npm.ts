import type { DependencyField } from '../../core/model.ts';
import type { PackageManagerAdapter, Publisher } from '../../core/ports.ts';
import { registrySettings, saveFlag, scopeOf } from './install-args.ts';

const QUIET = ['--no-audit', '--no-fund'] as const;

const SAVE_FLAG: Readonly<Record<DependencyField, string | undefined>> = {
  dependencies: undefined,
  devDependencies: '--save-dev',
  optionalDependencies: '--save-optional',
  peerDependencies: '--save-peer',
};

export const npm: PackageManagerAdapter = {
  name: 'npm',
  lockfiles: ['package-lock.json', 'npm-shrinkwrap.json'],

  install({ cwd, packages, registryUrl }) {
    return {
      command: 'npm',
      args: [
        'install',
        ...packages.map((pkg) => `${pkg.name}@${pkg.version}`),
        '--save-exact',
        ...saveFlag(packages, SAVE_FLAG),
        ...registrySettings(packages, registryUrl, (scope) =>
          scope === undefined ? '--registry' : `--${scope}:registry`,
        ),
        ...QUIET,
      ],
      cwd,
    };
  },

  cleanInstall({ cwd, hasLockfile, incremental }) {
    // Without a lockfile, a plain install must not create one, or the restore would not be exact.
    // `npm ci` deletes node_modules and installs it all; `npm install` follows the lockfile too, but
    // changes only what differs, which is a dev build or two.
    const args = !hasLockfile
      ? ['install', '--no-package-lock', ...QUIET]
      : incremental
        ? ['install', ...QUIET]
        : ['ci', ...QUIET];
    return { command: 'npm', args, cwd };
  },
};

/** Publishes every library, whichever package manager it uses: the staged folder is a plain package. */
export const npmPublisher: Publisher = {
  publish({ cwd, packageName, registryUrl, tag }) {
    // A user's `@scope:registry` beats `--registry` for a scoped package, so a dev build would go to
    // that registry, often the public one. Pinning the scope too keeps it on the local registry.
    const scope = scopeOf(packageName);
    return {
      command: 'npm',
      args: [
        'publish',
        // dryfit has built the library already. Its own prepublishOnly/prepack/prepare/postpublish
        // scripts would run again in the staging copy, which has no node_modules, on every save.
        '--ignore-scripts',
        `--registry=${registryUrl}`,
        ...(scope === undefined ? [] : [`--${scope}:registry=${registryUrl}`]),
        `--tag=${tag}`,
        '--provenance=false',
      ],
      cwd,
    };
  },

  publishAuthFiles({ registryUrl, credentials }) {
    // npm keys auth by registry URL without the protocol, always ending in a slash.
    const key = registryUrl.replace(/^https?:/, '').replace(/\/*$/, '/');
    const auth = btoa(`${credentials.username}:${credentials.password}`);
    return { '.npmrc': `${key}:_auth=${auth}\n` };
  },
};
