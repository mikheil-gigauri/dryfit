import semver from 'semver';
import { API_VERSION, type Health } from '../daemon/api.ts';

/**
 * Whether a CLI of `cliVersion` should replace the daemon it found.
 *
 * Replace it when the CLI is newer, so an update takes effect, or when the two speak different APIs.
 * Keep a newer daemon that speaks the same API: two CLIs side by side (a global install and
 * `npx @dryfit/cli@latest`, say) would otherwise restart the daemon on every switch and cancel
 * the job it is running.
 */
export function needsRestart(
  daemon: Pick<Health, 'version' | 'apiVersion'>,
  cliVersion: string,
  cliApiVersion: number = API_VERSION,
): boolean {
  if (daemon.apiVersion !== cliApiVersion) return true;
  if (daemon.version === cliVersion) return false;
  const [daemonVersion, cli] = [semver.valid(daemon.version), semver.valid(cliVersion)];
  // A version that is not semver cannot be ordered, so the old rule applies: any difference restarts.
  if (daemonVersion === null || cli === null) return true;
  return semver.lt(daemonVersion, cli);
}
