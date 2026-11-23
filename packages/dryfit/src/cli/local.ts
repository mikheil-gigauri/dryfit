import { spawn } from 'node:child_process';
import { closeSync, existsSync, openSync, realpathSync } from 'node:fs';
import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { homedir, userInfo } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import type { DaemonInfo, DryfitHome } from '../adapters/node/dryfit-home.ts';
import { NodeProcessRunner } from '../adapters/node/node-process-runner.ts';
import { readNpmRegistries, uplinksFrom } from '../adapters/registry/npm-uplinks.ts';
import { DryfitError } from '../core/errors.ts';
import { hasGuard } from '../core/guard/commit-guard.ts';
import { snapshotDir } from '../core/use-cases/shared.ts';
import type { Health, StatusView } from '../daemon/api.ts';
import { startDaemon } from '../daemon/daemon.ts';
import { installSkill, readSkill, uninstallSkill } from './agent-skill.ts';
import { DaemonClient } from './client.ts';
import { needsRestart } from './daemon-version.ts';
import { LAUNCH_AGENT_LABEL, launchAgentPlist } from './launchd.ts';
import type { LocalControl } from './main.ts';
import type { Output } from './output.ts';

const START_TIMEOUT_MS = 20_000;
/** How long a kickstarted login agent gets to answer before this CLI starts its own daemon. */
const KICKSTART_TIMEOUT_MS = 8_000;
const STOP_TIMEOUT_MS = 10_000;

interface Running {
  readonly info: DaemonInfo;
  readonly client: DaemonClient;
  readonly health: Health;
}

export interface LocalMachineOptions {
  readonly home: DryfitHome;
  readonly version: string;
  readonly env: NodeJS.ProcessEnv;
  /** The script that started this process; the daemon is started from the same one. */
  readonly entry: string;
  readonly out: Output;
  readonly err: Output;
  /** Ends `daemon run` (Ctrl-C, SIGTERM). */
  readonly signal: AbortSignal;
}

/** Starts, finds and stops the daemon, and checks the machine (ADR 0012). */
export class LocalMachine implements LocalControl {
  readonly #options: LocalMachineOptions;
  readonly #home: DryfitHome;

  constructor(options: LocalMachineOptions) {
    this.#options = options;
    this.#home = options.home;
  }

  async init(roots: readonly string[]) {
    await this.#home.ensure();
    const config = await this.#home.readConfig();
    await this.#home.writeConfig({ ...config, roots });
    await this.#home.ensureToken();
    return { home: this.#home.root, roots };
  }

  skill(): Promise<string> {
    return readSkill();
  }

  agent(action: 'install' | 'uninstall', skillsDir: string) {
    return action === 'install' ? installSkill(skillsDir) : uninstallSkill(skillsDir);
  }

  /** A client for a daemon of this version, starting or restarting one as needed. */
  async connect(): Promise<DaemonClient> {
    const running = await this.#find();
    if (running && !needsRestart(running.health, this.#options.version)) return running.client;
    if (running) await this.#stop(running);
    return this.#start();
  }

  async daemon(
    action: 'start' | 'stop' | 'restart' | 'status' | 'run' | 'install' | 'uninstall',
    json = false,
  ): Promise<number> {
    const { out } = this.#options;
    const printJson = (value: unknown, code = 0) => {
      out.line(JSON.stringify(value, null, 2));
      return code;
    };
    switch (action) {
      case 'run':
        return this.#runInForeground();
      case 'start': {
        const client = await this.connect();
        const health = await client.health();
        if (json)
          return printJson({
            running: true,
            version: health.version,
            pid: health.pid,
            apiUrl: client.baseUrl,
          });
        out.ok(`dryfit ${health.version} is running (pid ${health.pid}) at ${client.baseUrl}`);
        return 0;
      }
      case 'stop': {
        const running = await this.#find();
        if (running) {
          await this.#stop(running);
          if (json) return printJson({ ok: true });
          out.ok('Stopped dryfit');
          return 0;
        }
        if (json) {
          const info = await this.#home.readDaemonInfo();
          const stuck = info !== undefined && isAlive(info.pid);
          return printJson(stuck ? { ok: false, unresponsivePid: info.pid } : { ok: true }, stuck ? 1 : 0);
        }
        return this.#reportUnresponsive();
      }
      case 'restart': {
        const running = await this.#find();
        if (running) await this.#stop(running);
        else if ((await this.#reportUnresponsive()) !== 0) return 1;
        return this.daemon('start');
      }
      case 'status': {
        const running = await this.#find();
        if (!running) {
          if (json) return printJson({ running: false }, 1);
          out.line('dryfit is not running. Any command starts it.');
          return 1;
        }
        const { health, client } = running;
        if (json) {
          return printJson({
            running: true,
            version: health.version,
            pid: health.pid,
            startedAt: health.startedAt,
            apiUrl: client.baseUrl,
            registryUrl: health.registryUrl,
            atLogin: existsSync(agentPath()),
          });
        }
        out.ok(`dryfit ${health.version} running since ${health.startedAt} (pid ${health.pid})`);
        out.line(`  api       ${client.baseUrl}`);
        out.line(`  registry  ${health.registryUrl}`);
        out.line(`  at login  ${existsSync(agentPath()) ? 'yes (launchd)' : 'no'}`);
        return 0;
      }
      case 'install':
        return this.#installAgent();
      case 'uninstall':
        return this.#uninstallAgent();
    }
  }

  async doctor(out: Output, json: boolean): Promise<number> {
    const checks: { status: 'ok' | 'warn' | 'fail'; check: string; detail: string }[] = [];
    const add = (status: 'ok' | 'warn' | 'fail', check: string, detail = '') =>
      checks.push({ status, check, detail });
    const runner = new NodeProcessRunner({ baseEnv: this.#options.env, timeoutMs: 30_000 });

    const [major = 0, minor = 0] = process.versions.node.split('.').map(Number);
    const nodeOk = major > 22 || (major === 22 && minor >= 12);
    add(nodeOk ? 'ok' : 'fail', `Node ${process.versions.node}`, nodeOk ? '' : 'dryfit needs 22.12 or newer');

    const npm = await runner
      .run({ command: 'npm', args: ['--version'], cwd: homedir() })
      .catch(() => undefined);
    if (npm?.exitCode === 0) add('ok', `npm ${npm.stdout.trim()}`);
    else add('fail', 'npm', 'not found on PATH');

    let roots: readonly string[] = [];
    try {
      const config = await this.#home.readConfig();
      roots = config.roots;
      if (roots.length === 0)
        add('warn', 'Project roots', 'none set, so `dryfit consumers` finds nothing; run `dryfit init`');
      for (const root of roots) {
        add(
          existsSync(root) ? 'ok' : 'warn',
          `Root ${out.path(root)}`,
          existsSync(root) ? '' : 'does not exist',
        );
      }
    } catch (error) {
      add('fail', 'Config', error instanceof Error ? error.message : String(error));
    }

    const running = await this.#find().catch(() => undefined);
    let status: StatusView | undefined;
    if (!running) add('warn', 'Daemon', 'not running; any command starts it');
    else {
      const restarts = needsRestart(running.health, this.#options.version);
      add(
        restarts ? 'warn' : 'ok',
        `Daemon ${running.health.version} (pid ${running.health.pid})`,
        restarts
          ? `this CLI is ${this.#options.version}; the next command restarts it`
          : running.health.version === this.#options.version
            ? ''
            : `newer than this CLI (${this.#options.version}), so it is kept`,
      );
      const ping = await fetch(`${running.health.registryUrl}-/ping`, {
        signal: AbortSignal.timeout(5_000),
      }).catch(() => undefined);
      add(
        ping?.ok ? 'ok' : 'fail',
        `Registry ${running.health.registryUrl}`,
        ping?.ok ? '' : 'not answering',
      );
      status = await running.client.call('status', {}).catch(() => undefined);
    }

    try {
      const registries = await readNpmRegistries(runner, {
        cwd: this.#options.env.HOME ?? homedir(),
        env: this.#options.env,
      });
      const own = running?.health.registryUrl ?? 'http://127.0.0.1:0/';
      for (const [name, uplink] of Object.entries(uplinksFrom({ ...registries, ownRegistry: own }))) {
        const scope = uplink.scopes ? ` for ${uplink.scopes.join(', ')}` : '';
        add(
          'ok',
          `Proxies ${name}${scope}`,
          uplink.auth ? 'with your npm credentials' : 'without credentials',
        );
      }
    } catch {
      add('warn', 'npm registries', 'could not read your npm config');
    }

    for (const link of status?.links ?? []) {
      const where = out.path(link.consumer);
      const snapshot = join(snapshotDir({ home: this.#home.root }, link.consumer), 'meta.json');
      if (!existsSync(snapshot))
        add('fail', `Snapshot for ${where}`, 'missing, so restore cannot work; reinstall from git');
      if (link.guard && !(await guardPresent(runner, link.consumer))) {
        add(
          'warn',
          `Commit guard in ${where}`,
          'missing (Husky may have regenerated hooks); the next sync adds it back',
        );
      }
      if (link.status === 'failed')
        add('warn', `${link.library} in ${where}`, 'last install failed; run `dryfit sync`');
    }
    for (const warning of status?.warnings ?? []) {
      add('warn', `Group ${warning.group}`, `runs different versions of ${warning.library}`);
    }
    if (process.platform === 'darwin') {
      if (!existsSync(agentPath())) add('ok', 'Start at login', 'off (`dryfit daemon install`)');
      else if ((await this.#launchctl(['print', `gui/${userInfo().uid}/${LAUNCH_AGENT_LABEL}`])) === 0)
        add('ok', 'Start at login', 'launchd agent loaded');
      else add('warn', 'Start at login', 'agent installed but not loaded; run `dryfit daemon install` again');
    }

    if (json) out.line(JSON.stringify(checks, null, 2));
    else {
      for (const { status: state, check, detail } of checks) {
        const text = detail ? `${check} ${out.dim(`— ${detail}`)}` : check;
        if (state === 'ok') out.ok(text);
        else if (state === 'warn') out.warn(text);
        else out.fail(text);
      }
    }
    return checks.some((check) => check.status === 'fail') ? 1 : 0;
  }

  /**
   * The daemon `daemon.json` describes, if it answers as that daemon. A pid can be reused after a crash
   * or reboot and a port taken by something else, so nothing is trusted (or sent the token, or
   * signalled) until health confirms both.
   */
  async #find(): Promise<Running | undefined> {
    const info = await this.#home.readDaemonInfo();
    if (!info || !isAlive(info.pid)) return undefined;
    const client = new DaemonClient(`http://127.0.0.1:${info.port}/`, await this.#home.ensureToken());
    const health = await client.health().catch(() => undefined);
    if (health?.name !== 'dryfit' || health.pid !== info.pid) return undefined;
    return { info, client, health };
  }

  /** Explains a `daemon.json` whose process is alive but does not answer as dryfit; signals nothing. */
  async #reportUnresponsive(): Promise<number> {
    const { out } = this.#options;
    const info = await this.#home.readDaemonInfo();
    if (!info || !isAlive(info.pid)) {
      out.line('dryfit is not running.');
      return 0;
    }
    out.fail(`${out.path(this.#home.paths.daemon)} names pid ${info.pid}, which does not answer as dryfit.`);
    out.line(
      out.dim(
        `If that is a stuck dryfit daemon, end it with \`kill ${info.pid}\`; otherwise delete the file.`,
      ),
    );
    return 1;
  }

  async #start(): Promise<DaemonClient> {
    const { env, entry } = this.#options;
    await mkdir(this.#home.paths.logs, { recursive: true });

    let exited: number | null | undefined;
    // An installed but unloaded agent fails to kickstart; starting the daemon directly still works.
    let kickstarted =
      existsSync(agentPath()) &&
      (await this.#launchctl(['kickstart', `gui/${userInfo().uid}/${LAUNCH_AGENT_LABEL}`])) === 0;
    if (kickstarted) {
      // The agent runs the dryfit it was installed from, which may be another version than this one,
      // or a node that is gone. Then this version is started directly instead.
      const deadline = Date.now() + KICKSTART_TIMEOUT_MS;
      let other: Running | undefined;
      while (Date.now() < deadline) {
        const running = await this.#find();
        if (running?.health.version === this.#options.version) return running.client;
        if (running) {
          other = running;
          break;
        }
        await sleep(100);
      }
      if (other) {
        // A clean shutdown exits 0, which launchd's KeepAlive leaves alone.
        await this.#stop(other);
        this.#options.out.warn(
          `The login agent starts dryfit ${other.health.version}; run \`dryfit daemon install\` to start ${this.#options.version} at login.`,
        );
      }
      kickstarted = false;
    }
    if (!kickstarted) {
      const log = openSync(this.#home.paths.log, 'a');
      try {
        const child = spawn(process.execPath, [...process.execArgv, entry, 'daemon', 'run'], {
          detached: true,
          stdio: ['ignore', log, log],
          env,
        });
        child.once('exit', (code) => (exited = code));
        child.once('error', () => (exited = null));
        child.unref();
      } finally {
        closeSync(log); // the child has its own copy
      }
    }

    const deadline = Date.now() + START_TIMEOUT_MS;
    while (Date.now() < deadline) {
      const running = await this.#find();
      if (running?.health.version === this.#options.version) return running.client;
      // Checked after one more look: a daemon that lost the port to a concurrent start exits at once,
      // while the winner is up and serving.
      if (exited !== undefined) break;
      await sleep(100);
    }
    const tail = (await readFile(this.#home.paths.log, 'utf8').catch(() => ''))
      .trimEnd()
      .split('\n')
      .slice(-15)
      .join('\n');
    throw new DryfitError(
      'daemon-failed',
      exited !== undefined
        ? 'The dryfit daemon stopped right after starting'
        : 'The dryfit daemon did not come up in time',
      { output: tail },
    );
  }

  /** Stops a daemon `#find` has confirmed, so the pid it signals is known to be dryfit's. */
  async #stop({ info, client }: Running): Promise<void> {
    await client.call('shutdown', {}).catch(() => signal(info.pid, 'SIGTERM'));
    const deadline = Date.now() + STOP_TIMEOUT_MS;
    while (isAlive(info.pid) && Date.now() < deadline) await sleep(100);
    if (isAlive(info.pid)) signal(info.pid, 'SIGKILL');
    await this.#home.removeDaemonInfo(info.pid);
  }

  async #runInForeground(): Promise<number> {
    const { home, version, env, err, signal: stop } = this.#options;
    const log = (message: string) => err.line(`${new Date().toISOString()} ${message}`);
    let daemon: Awaited<ReturnType<typeof startDaemon>>;
    try {
      daemon = await startDaemon({ home, version, env, log });
    } catch (error) {
      log(error instanceof Error ? error.message : String(error));
      return 1;
    }
    // A signal that arrived while it was starting has already fired; it still means stop.
    if (stop.aborted) void daemon.stop();
    else stop.addEventListener('abort', () => void daemon.stop(), { once: true });
    await daemon.stopped;
    log('stopped');
    return 0;
  }

  async #installAgent(): Promise<number> {
    const { out, env } = this.#options;
    if (process.platform !== 'darwin') {
      out.line('Starting at login uses launchd, which is macOS only.');
      return 1;
    }
    await mkdir(join(homedir(), 'Library', 'LaunchAgents'), { recursive: true });
    await mkdir(this.#home.paths.logs, { recursive: true });
    const plist = launchAgentPlist({
      node: process.execPath,
      entry: realpathSync(this.#options.entry),
      path: env.PATH ?? '/usr/bin:/bin',
      log: this.#home.paths.log,
      env: agentEnvironment(env),
    });

    const running = await this.#find();
    if (running) await this.#stop(running);
    await this.#launchctl(['bootout', `gui/${userInfo().uid}/${LAUNCH_AGENT_LABEL}`]);
    await writeFile(agentPath(), plist);
    const result = await this.#launchctl(['bootstrap', `gui/${userInfo().uid}`, agentPath()]);
    if (result !== 0) {
      out.fail(`launchctl could not load ${agentPath()}`);
      return 1;
    }
    out.ok(`dryfit now starts at login (${out.path(agentPath())})`);
    return 0;
  }

  async #uninstallAgent(): Promise<number> {
    const { out } = this.#options;
    if (!existsSync(agentPath())) {
      out.line('dryfit is not set to start at login.');
      return 0;
    }
    await this.#launchctl(['bootout', `gui/${userInfo().uid}/${LAUNCH_AGENT_LABEL}`]);
    await rm(agentPath(), { force: true });
    out.ok('dryfit no longer starts at login');
    return 0;
  }

  async #launchctl(args: string[]): Promise<number> {
    const result = await new NodeProcessRunner({ baseEnv: this.#options.env })
      .run({ command: 'launchctl', args, cwd: homedir() })
      .catch(() => undefined);
    return result?.exitCode ?? 1;
  }
}

function agentPath(): string {
  return join(homedir(), 'Library', 'LaunchAgents', `${LAUNCH_AGENT_LABEL}.plist`);
}

function isAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    // EPERM: the process exists but belongs to someone else.
    return error instanceof Error && 'code' in error && error.code === 'EPERM';
  }
}

function signal(pid: number, name: NodeJS.Signals): void {
  try {
    process.kill(pid, name);
  } catch {
    // Already gone.
  }
}

async function guardPresent(runner: NodeProcessRunner, consumer: string): Promise<boolean> {
  const result = await runner
    .run({ command: 'git', args: ['rev-parse', '--git-path', 'hooks'], cwd: consumer })
    .catch(() => undefined);
  if (result?.exitCode !== 0) return true; // not a repository: nothing to guard
  const hook = resolve(consumer, result.stdout.trim(), 'pre-commit');
  if (!(await stat(hook).catch(() => undefined))) return false;
  return hasGuard(await readFile(hook, 'utf8'));
}

/**
 * What the login agent keeps from the shell that installed it. launchd starts it with almost nothing,
 * so without these, installs behind a proxy or a company CA work from a terminal and fail after a
 * reboot. Only settings, never secrets: the plist is readable by anyone on the Mac, so a token an
 * npmrc expands (`${NPM_TOKEN}`) belongs in the npmrc itself.
 */
export function agentEnvironment(env: NodeJS.ProcessEnv): Record<string, string> {
  const kept =
    /^(DRYFIT_HOME|NODE_EXTRA_CA_CERTS|SSL_CERT_FILE|SSL_CERT_DIR|NPM_CONFIG_(REGISTRY|CAFILE|STRICT_SSL))$|^(https?_proxy|all_proxy|no_proxy)$/i;
  return Object.fromEntries(
    Object.entries(env).filter(
      (entry): entry is [string, string] =>
        kept.test(entry[0]) && entry[1] !== undefined && !/^npm_/.test(entry[0]),
    ),
  );
}
