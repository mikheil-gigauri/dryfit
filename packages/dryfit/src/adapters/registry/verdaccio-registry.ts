import { createHash, randomBytes } from 'node:crypto';
import { chmod, mkdir, writeFile } from 'node:fs/promises';
import type { IncomingMessage, RequestListener, Server, ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { join } from 'node:path';
import type { runServer as RunServer } from 'verdaccio';
import { DryfitError } from '../../core/errors.ts';
import type { RegistryCredentials } from '../../core/ports.ts';

const HOST = '127.0.0.1';
const USER = 'dryfit';

export interface Uplink {
  /** Registry URL to fetch packages dryfit does not hold, e.g. `https://registry.npmjs.org/`. */
  readonly url: string;
  /** Credentials for a private registry, held in memory only. */
  readonly auth?: { readonly type: 'bearer' | 'basic'; readonly token: string };
  /** Scopes this registry serves, e.g. `['@corp']`. Without scopes it serves everything else. */
  readonly scopes?: readonly string[];
}

export interface VerdaccioRegistryOptions {
  /** Folder for packages and auth data, e.g. `~/.dryfit/registry`. */
  readonly storage: string;
  /** Port to listen on; 0 picks a free one. */
  readonly port: number;
  /** Registries to proxy for packages dryfit has not published. None by default. */
  readonly uplinks?: Readonly<Record<string, Uplink>>;
  readonly logLevel?: 'fatal' | 'error' | 'warn' | 'info';
  /** Reading also needs credentials. Only tests use this, to stand in for a private registry. */
  readonly requireAuthToRead?: boolean;
}

/**
 * The local registry (ADR 0002): Verdaccio, started in-process.
 *
 * Hardening beyond Verdaccio's defaults, because it serves unreleased and often private code:
 * - it listens on 127.0.0.1 only;
 * - its storage folder is private to the current user: it holds Verdaccio's token-signing secret;
 * - publishing needs HTTP Basic auth as the single `dryfit` user, whose random password is created on
 *   every start and only ever held in memory (htpasswd keeps a hash). Registration is disabled and the
 *   user exists before the port opens, so no other process can claim publish rights, and credentials
 *   from an earlier start stop working;
 * - any request carrying an `Origin` header, or a `Host` other than the loopback address, is refused.
 *   The npm CLI sends neither, while a web page always sends `Origin` cross-site and a DNS-rebinding
 *   page sends a foreign `Host`; without this, any site you visit could read your dev builds through
 *   Verdaccio's permissive CORS.
 */
export class VerdaccioRegistry {
  readonly url: string;
  readonly credentials: RegistryCredentials;
  readonly #server: Server;

  private constructor(server: Server, url: string, credentials: RegistryCredentials) {
    this.#server = server;
    this.url = url;
    this.credentials = credentials;
  }

  static async start(options: VerdaccioRegistryOptions): Promise<VerdaccioRegistry> {
    await mkdir(options.storage, { recursive: true, mode: 0o700 });
    await chmod(options.storage, 0o700);

    const credentials = { username: USER, password: randomBytes(32).toString('base64url') };
    const htpasswd = join(options.storage, 'htpasswd');

    const entries = Object.entries(options.uplinks ?? {});
    const uplinks = Object.fromEntries(
      entries.map(([name, { url, auth }]) => [
        name,
        { url, timeout: '30s', max_fails: 2, ...(auth && { auth }) },
      ]),
    );
    const rule = (proxy: readonly string[]) => ({
      access: options.requireAuthToRead ? '$authenticated' : '$all',
      publish: '$authenticated',
      unpublish: '$authenticated',
      ...(proxy.length > 0 && { proxy: [...proxy] }),
    });
    // Verdaccio takes the first matching rule, so scoped rules come before the catch-all.
    const scoped = entries.flatMap(([name, uplink]) =>
      (uplink.scopes ?? []).map((scope) => [`${scope}/*`, rule([name])] as const),
    );
    const general = entries.filter(([, uplink]) => !uplink.scopes?.length).map(([name]) => name);
    // Loaded here, not at the top: Verdaccio takes about 300 ms to import, and only the daemon needs it.
    const { runServer } = await import('verdaccio');
    const server: Server = await runServer({
      self_path: join(options.storage, 'config.yaml'),
      storage: options.storage,
      auth: { htpasswd: { file: htpasswd, max_users: -1 } },
      uplinks,
      packages: { ...Object.fromEntries(scoped), '**': rule(general) },
      web: { enable: false },
      log: { type: 'stdout', format: 'json', level: options.logLevel ?? 'warn' },
    } as Parameters<typeof RunServer>[0]);

    try {
      guardAgainstBrowsers(server);
      const port = await listen(server, options.port);
      // Only once the port is ours: a second start that loses it must not replace the running
      // registry's credentials. Until then the file still holds an earlier start's user, whose
      // password nobody knows, so the user exists before the port opens either way.
      // {SHA} is unsalted, which is fine for 256 random bits: there is nothing to guess.
      const hash = createHash('sha1').update(credentials.password).digest('base64');
      await writeFile(htpasswd, `${USER}:{SHA}${hash}\n`, { mode: 0o600 });
      await chmod(htpasswd, 0o600);
      return new VerdaccioRegistry(server, `http://${HOST}:${port}/`, credentials);
    } catch (error) {
      await close(server);
      throw error;
    }
  }

  async stop(): Promise<void> {
    await close(this.#server);
  }
}

function guardAgainstBrowsers(server: Server): void {
  const handlers = server.listeners('request') as RequestListener[];
  server.removeAllListeners('request');
  server.on('request', (req: IncomingMessage, res: ServerResponse) => {
    if (req.headers.origin !== undefined || !isLoopbackHost(req.headers.host, server)) {
      res
        .writeHead(403, { 'content-type': 'text/plain' })
        .end('dryfit registry: browser requests are refused\n');
      return;
    }
    for (const handler of handlers) handler(req, res);
  });
}

function isLoopbackHost(host: string | undefined, server: Server): boolean {
  const { port } = server.address() as AddressInfo;
  return host === `${HOST}:${port}` || host === `localhost:${port}`;
}

function listen(server: Server, port: number): Promise<number> {
  return new Promise((resolve, reject) => {
    const onError = (error: NodeJS.ErrnoException) => {
      const reason = error.code === 'EADDRINUSE' ? `port ${port} is already in use` : error.message;
      reject(new DryfitError('registry-failed', `The local registry could not start: ${reason}`, { port }));
    };
    server.once('error', onError);
    server.listen(port, HOST, () => {
      server.off('error', onError);
      resolve((server.address() as AddressInfo).port);
    });
  });
}

function close(server: Server): Promise<void> {
  return new Promise((resolve) => {
    if (!server.listening) return resolve();
    server.close(() => resolve());
    server.closeAllConnections();
  });
}
