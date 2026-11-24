import type { PackageManagerName } from './package-manager/detect.ts';

export const DEPENDENCY_FIELDS = [
  'dependencies',
  'devDependencies',
  'optionalDependencies',
  'peerDependencies',
] as const;

export type DependencyField = (typeof DEPENDENCY_FIELDS)[number];

/** The parts of a package.json dryfit reads. Unknown fields are preserved untouched. */
export interface Manifest {
  readonly name?: string;
  readonly version?: string;
  readonly packageManager?: string;
  readonly dependencies?: Readonly<Record<string, string>>;
  readonly devDependencies?: Readonly<Record<string, string>>;
  readonly optionalDependencies?: Readonly<Record<string, string>>;
  readonly peerDependencies?: Readonly<Record<string, string>>;
  readonly [field: string]: unknown;
}

/** A process to run. Adapters describe commands; the ProcessRunner port executes them. */
export interface CommandSpec {
  readonly command: string;
  readonly args: readonly string[];
  readonly cwd: string;
}

export interface LibraryRecord {
  /** The package name, which is also the library's identity. */
  readonly name: string;
  /** Absolute path of the folder holding the library's source package.json. */
  readonly root: string;
  /** Absolute path of the folder that gets published (for ng-packagr libraries, the dist folder). */
  readonly publishDir: string;
  /** Command that produces publishDir. Omitted when the library publishes its sources. */
  readonly build?: CommandSpec | undefined;
  readonly lastPublishedVersion?: string | undefined;
  /**
   * The dev version of each registered library this dev build depends on directly, as its manifest
   * pinned them (ADR 0014). Missing on dev builds published before dryfit recorded it.
   */
  readonly pinnedSiblings?: Readonly<Record<string, string>> | undefined;
  /** Whether the daemon rebuilds and syncs the library when its sources change. */
  readonly watch?: boolean | undefined;
}

export type LinkStatus = 'pending' | 'installed' | 'failed';

export interface LinkRecord {
  readonly library: string;
  /** Absolute path of the consumer project (the folder that owns its lockfile). */
  readonly consumer: string;
  readonly status: LinkStatus;
  readonly installedVersion?: string | undefined;
  /** Why the last install failed: the end of the package manager's output. Only on failed links. */
  readonly message?: string | undefined;
  /** Whether the consumer's git pre-commit hook carries the commit guard (ADR 0012). */
  readonly guard?: boolean | undefined;
}

/** Consumers that run together, such as a federation host and its remotes (ADR 0005). */
export interface GroupRecord {
  readonly name: string;
  /** Absolute consumer paths, in the order they were given. */
  readonly consumers: readonly string[];
}

export interface DryfitState {
  readonly libraries: readonly LibraryRecord[];
  readonly links: readonly LinkRecord[];
  readonly groups: readonly GroupRecord[];
}

export const EMPTY_STATE: DryfitState = { libraries: [], links: [], groups: [] };

/** What a snapshot remembers about a consumer, stored next to the copied files. */
export interface SnapshotMeta {
  readonly consumer: string;
  readonly packageManager: PackageManagerName;
  /** Lockfiles present at the time of linking; empty if the consumer had none. */
  readonly lockfiles: readonly string[];
  readonly createdAt: string;
  /**
   * Config files copied under `configs/` for a live reload setting (ADR 0007). Absent in snapshots
   * taken before dryfit kept one, whose consumers are then left without it.
   */
  readonly configFiles?: readonly string[];
}
