import type { ConsumerIntegration, LiveReloadSetting, ProjectInfo } from '../ports.ts';

/** The config files a project has for the live reload settings of its detected integrations (ADR 0007). */
export function liveReloadFiles(
  project: ProjectInfo,
  integrations: readonly ConsumerIntegration[],
): { readonly file: string; readonly setting: LiveReloadSetting }[] {
  return integrations.flatMap((integration) => {
    const setting = integration.liveReload;
    if (setting === undefined || !integration.detect(project)) return [];
    return setting.files
      .filter((file) => project.rootFiles.includes(file))
      .map((file) => ({ file, setting }));
  });
}

/** The setting a config file holds, whether or not its integration is still detected. */
export function liveReloadSettingFor(
  file: string,
  integrations: readonly ConsumerIntegration[],
): LiveReloadSetting | undefined {
  return integrations.find((integration) => integration.liveReload?.files.includes(file))?.liveReload;
}
