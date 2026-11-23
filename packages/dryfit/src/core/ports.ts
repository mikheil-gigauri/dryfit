import type { CommandSpec, DependencyField, DryfitState, Manifest } from './model.ts';
import type { PackageManagerName } from './package-manager/detect.ts';

/** File system access. Paths are absolute and POSIX-style. */
export interface FileSystem {
  /** Returns undefined when the file does not exist. */
  readText(path: string): Promise<string | undefined>;
  /** Creates missing parent folders. A private file is readable and writable by its owner only. */
  writeText(path: string, content: string, options?: { readonly private?: boolean }): Promise<void>;
  exists(path: string): Promise<boolean>;
  /** Entries directly inside a folder, sorted by name. Empty when the folder does not exist. */
  readDir(path: string): Promise<readonly DirEntry[]>;
  /** Removes a file or a folder recursively. Does nothing when the path does not exist. */
  remove(path: string): Promise<void>;
  /**
   * Copies a folder recursively, empty folders included, skipping entries whose name is in `exclude` at
   * any depth. Rejects when `from` does not exist.
   */
  copyDir(from: string, to: string, options: { readonly exclude: readonly string[] }): Promise<void>;
}

export interface DirEntry {
  readonly name: string;
  readonly isDirectory: boolean;
}

export interface CommandResult {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
}

/** A command to run, with variables set for it alone on top of the runner's environment. */
export interface RunSpec extends CommandSpec {
  readonly env?: Readonly<Record<string, string>>;
}

export interface ProcessRunner {
  run(spec: RunSpec): Promise<CommandResult>;
}

export interface Clock {
  now(): Date;
}

export interface StateStore {
  load(): Promise<DryfitState>;
  save(state: DryfitState): Promise<void>;
}

export interface InstallPackage {
  readonly name: string;
  readonly version: string;
  /** Keeps the package in the manifest field it was already declared in. */
  readonly dependencyField: DependencyField;
}

/**
 * Packages installed in one package manager run, so dev builds that pin each other exactly are
 * resolved together (ADR 0014). When they are declared in different fields, adapters pass no save
 * flag, and every supported package manager keeps each package where it already is.
 */
export interface InstallSpec {
  readonly cwd: string;
  readonly packages: readonly InstallPackage[];
  readonly registryUrl: string;
}

export interface PublishSpec {
  readonly cwd: string;
  /** The package being published, so a scoped one can be pinned to the local registry. */
  readonly packageName: string;
  readonly registryUrl: string;
  readonly tag: string;
}

export interface CleanInstallSpec {
  readonly cwd: string;
  /** Whether a lockfile exists to install from exactly. */
  readonly hasLockfile: boolean;
  /**
   * Whether node_modules may be reused, so only what differs from the lockfile is touched. A manager that
   * already installs that way ignores it; npm otherwise deletes node_modules and installs everything.
   */
  readonly incremental?: boolean;
}

/** HTTP Basic credentials for the local registry. The password is random and changes on every start. */
export interface RegistryCredentials {
  readonly username: string;
  readonly password: string;
}

/**
 * Everything dryfit needs from a package manager to install into a consumer (ADR 0006).
 * Implementations are pure: they describe commands, and a ProcessRunner runs them.
 */
export interface PackageManagerAdapter {
  readonly name: PackageManagerName;
  /** Lockfile names this manager writes, most common first. */
  readonly lockfiles: readonly string[];
  install(spec: InstallSpec): RunSpec;
  cleanInstall(spec: CleanInstallSpec): RunSpec;
}

/** Publishes a staged package to the local registry. npm does it for every library (ADR 0006). */
export interface Publisher {
  publish(spec: PublishSpec): RunSpec;
  /**
   * Files to place in the staging folder so `publish` authenticates, keyed by file name. Files rather
   * than flags keep credentials out of the process list; the staging folder is deleted afterwards.
   */
  publishAuthFiles(spec: {
    readonly registryUrl: string;
    readonly credentials: RegistryCredentials;
  }): Readonly<Record<string, string>>;
}

export type PackageManagerAdapters = Readonly<Partial<Record<PackageManagerName, PackageManagerAdapter>>>;

/** What integrations and use cases know about a project folder. */
export interface ProjectInfo {
  readonly root: string;
  readonly manifest: Manifest;
  /** Names of the entries directly inside `root`. */
  readonly rootFiles: readonly string[];
  /** Parsed contents of the config files integrations asked for, keyed by file name. */
  readonly configs: ReadonlyMap<string, unknown>;
}

/** Framework knowledge about caches that hide a freshly installed library (ADR 0007). */
export interface ConsumerIntegration {
  readonly id: string;
  /** Root-level JSON files this integration wants parsed into `ProjectInfo.configs`. */
  readonly configFiles?: readonly string[];
  detect(project: ProjectInfo): boolean;
  /** Cache folders relative to the project root. */
  cachePaths(project: ProjectInfo): readonly string[];
}

export type DryfitEvent =
  | { readonly type: 'build:started'; readonly library: string }
  | { readonly type: 'build:succeeded'; readonly library: string }
  | { readonly type: 'build:failed'; readonly library: string; readonly output: string }
  | { readonly type: 'publish:succeeded'; readonly library: string; readonly version: string }
  | {
      readonly type: 'install:started';
      readonly library: string;
      readonly consumer: string;
      readonly version: string;
    }
  | {
      readonly type: 'install:succeeded';
      readonly library: string;
      readonly consumer: string;
      readonly version: string;
    }
  | {
      readonly type: 'install:failed';
      readonly library: string;
      readonly consumer: string;
      readonly version: string;
      readonly output: string;
    }
  | { readonly type: 'caches:cleared'; readonly consumer: string; readonly paths: readonly string[] }
  | {
      readonly type: 'consumer:restored';
      readonly consumer: string;
      /** Set when only this library was restored and the consumer's other links were kept. */
      readonly library?: string | undefined;
      readonly ok: boolean;
    };

export interface EventSink {
  emit(event: DryfitEvent): void;
}

/** Everything a use case may touch. Assembled by the daemon, or by fakes in tests. */
export interface CoreDeps {
  readonly fs: FileSystem;
  readonly process: ProcessRunner;
  readonly clock: Clock;
  readonly state: StateStore;
  readonly events: EventSink;
  readonly packageManagers: PackageManagerAdapters;
  readonly publisher: Publisher;
  readonly integrations: readonly ConsumerIntegration[];
  /** The local registry's base URL, e.g. `http://127.0.0.1:4873/`. */
  readonly registryUrl: string;
  /** What lets dryfit publish to the local registry. */
  readonly registryCredentials: RegistryCredentials;
  /** dryfit's own data folder, e.g. `~/.dryfit`. */
  readonly home: string;
}
